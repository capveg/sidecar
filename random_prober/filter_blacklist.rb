#!/usr/bin/ruby 

# for grr.cs's stupid setup
$: << '/usr/local/lib/ruby/1.8/i386-linux-gnu'

begin
	require 'undns'
	rescue LoadError => e
		$stderr.puts "Need to install undns for this script to work"
		$stderr.puts "run `make undns` from the base directory Makefile to build and install"
	exit
end
require 'srclient'
require 'scriptroute/ally'

require "nspring-utils"

class BlackList
	def initialize 
	@blacklistPrefixes= [
	# clear things that should not be probed
		"0.0.0.0/32 ip",
		"10.0.0.0/8 ip",
		"192.168.0/16 ip",
		"172.16.0.0/12 ip",
		"224.0.0.0/4 ip" ,
	# verizon complaint about TCP, PL#20992,PL#21000
	# not clearly in violation of http://global.mci.com/terms/a_u_p, but whatever
		"63.65.130.45/32 tcp",
		"129.250.9.70/32 tcp",
		"146.188.5.93/32 tcp",
		"146.188.8.162/32 tcp",
		"146.188.8.166/32 tcp",
		"146.188.15.229/32 tcp",
		"154.54.12.250/32 tcp",
		"208.175.172.170/32 tcp",
		]
	end
	def filter(file,goodIpFile)
		nIPs=0
		nrejectIPs=0
		backlistfile="blacklist.dat"
		makeBlackList(backlistfile)
		Undns.origins_init(backlistfile)    # load blacklist
		File.open(goodIpFile,File::RDWR) { |out|
			File.open(file).each{ |line|
				line.chomp!
				if Undns.origin_for_address_str(line) == 0
					out.puts line
					nIPs+=1
				else
					nrejectIPs+=1
				end
			}
		}
		$stderr.puts "#{nrejectIPs+nIPs} Total Ips: #{nrejectIPs} rejected"
		return nIPs
	end

	def makeBlackList(blacklist)
		# snag blacklist from scriptroute
		Kernel.system("wget -O #{blacklist} http://www.scriptroute.org/blacklist")
		out=File.open(blacklist,"a")
		out.puts "# add our own local blacklist info"
		@blacklistPrefixes.each{  |line|
			out.puts "#{line} # capveg"
		}
		out.close
		# remap ip/tcp/udp/icmp to filter code 7/1/2/4
		Kernel.system("perl -pi -e 's/ ip / 7 /g; s/ tcp / 1 /g; s/ udp / 2 /g; s/ icmp / 4 /g' #{blacklist}")
	end
end


if __FILE__ == $0
	bl = BlackList.new
	if ARGV.length == 0 
		bl.filter('/dev/stdin','/dev/stdout')
	elsif ARGV.length == 1
		bl.filter(ARGV[0],'/dev/stdout')
	elsif ARGV.length == 2
		bl.filter(ARGV[0],ARGV[1])
	else
		raise "Confusing Number of args:: #{ARGV.length}"
	end
end
