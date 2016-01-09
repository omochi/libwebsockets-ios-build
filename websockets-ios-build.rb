#!/usr/bin/env ruby

require "pathname"
require "shellwords"

# platform: iphone, iphone-simulator
# arch: armv7, arm64, i386, x86_64
# configuration: Debug, Release

class App
	attr_reader :script_dir
	attr_reader :websockets_dir

	attr_reader :platform
	attr_reader :arch
	attr_reader :configuration

	attr_reader :bitcode_enabled

	def xcode_platform
		case platform
		when "iphone"
			return "iphoneos"
		when "iphone-simulator"
			return "iphonesimulator"
		else
			raise "invalid platform: #{platform}"
		end
	end
	def xcode_arch
		arch
	end
	def libwebsockets_dir
		script_dir + "libwebsockets"
	end
	def openssl_dir
		script_dir + "OpenSSL-for-iPhone"
	end
	def main
		@script_dir = Pathname(__FILE__).parent.expand_path
		@configuration = "Release"

		subcmd = "build"
		if 0 < ARGV.length
			subcmd = ARGV[0]
		end

		case subcmd
		when "build"
			build
		when "clean"
			clean
		else
			raise "undefined sub command: #{subcmd}"
		end
	end
	def make_output_dir
		dir = output_dir
		dir.mkpath
		(dir + ".keep").binwrite("")
	end
	def set_target(platform, arch)
		@platform = platform
		@arch = arch
	end
	def output_dir
		script_dir + "out"
	end
	def xcode_build_dir
		output_dir + "xcode-build"
	end
	def target_build_dir
		xcode_build_dir + "#{platform}-#{arch}"
	end
	def configured_target_build_dir
		target_build_dir + "#{configuration}-#{xcode_platform}"
	end
	def lib_dir
		output_dir + "lib"
	end
	def include_dir
		output_dir + "include"
	end
	def build
		if ! libwebsockets_dir.exist?
			puts "fetch libwebsockets"
			Dir.chdir(script_dir.to_s)
			cmd = ["git", "clone", 
				"https://github.com/warmcat/libwebsockets.git"].shelljoin
			exec(cmd)
		end
		if ! openssl_dir.exist?
			puts "fetch OpenSSL-for-iPhone"
			Dir.chdir(script_dir.to_s)
			cmd = ["git", "clone", 
				"https://github.com/omochi/OpenSSL-for-iPhone.git"].shelljoin
			exec(cmd)
		end
		if ! (openssl_dir + "lib/libssl.a").exist?
			Dir.chdir(openssl_dir.to_s)
			puts "build openssl"
			cmd = ["./build-libssl.sh"].shelljoin
			exec(cmd)
		end

		make_output_dir

		targets = [
			["iphone", "armv7"],
			["iphone", "arm64"],
			["iphone-simulator", "i386"],
			["iphone-simulator", "x86_64"]
		]

		for target in targets
			set_target(*target)
			build_target
		end

		lib_dir.mkpath
		lib_name = "libwebsockets.a"
		fat_lib = lib_dir + lib_name
		if ! fat_lib.exist?
			thin_libs = targets
				.map {|target|
					set_target(*target)

					configured_target_build_dir + lib_name
				}
			make_fat_lib(thin_libs, fat_lib)
		end

		if ! include_dir.exist?
			puts "copy headers"
			include_dir.mkpath
			Dir.chdir((libwebsockets_dir + "lib").to_s)
			for file_str in Dir.glob(["**/*"]).each
				file = Pathname(file_str)
				dest_file = include_dir + file
				if file.directory?
					dest_file.mkpath
				elsif file.extname == ".h"
					skips = [
						"private-libwebsockets.h",
						"lextable.h",
						"lextable-strings.h",
						"huftable.h",
						"getifaddrs.h"
					]
					if skips.include?(file.basename.to_s)
						next
					end
					FileUtils.copy(file, dest_file)
				end
			end
		end
	end
	def build_target
		dir = target_build_dir
		dir.mkpath
		Dir.chdir(script_dir.to_s)

		cmd = ["xcodebuild", "-project", "websockets.xcodeproj",
			"-target", "websockets",
			"-configuration", configuration,
			"-arch", xcode_arch,
			"-sdk", xcode_sdk_path,
			"SYMROOT=#{dir.to_s}"
			].shelljoin
		exec(cmd)
	end
	def make_fat_lib(thin_libs, fat_lib)
		puts "make fat lib: #{fat_lib.basename.to_s}"
		cmd = ["lipo", "-create"] +
			thin_libs.map{|x| x.to_s } +
			["-output", fat_lib.to_s]
		exec(cmd.shelljoin)
	end
	def clean
		if output_dir.exist?
			output_dir.rmtree
		end
		make_output_dir
	end
	def xcode_tool_path(name)
		exec_capture(["xcrun", "-sdk", xcode_platform, "-f", name].shelljoin).strip
	end
	def xcode_sdk_path
		exec_capture(["xcrun", "-sdk", xcode_platform, "--show-sdk-path"].shelljoin).strip
	end
	def exec(command)
		ret = system(command)
		if ! ret
			raise "exec failed: status=#{$?}, command=#{command}"
		end
	end
	def exec_capture(command)
		`#{command}`
	end
end

app = App.new
app.main()