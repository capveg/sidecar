#!/usr/bin/ruby 

$sidecarDir=ENV['SIDECARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"

$: << "#{$sidecarDir}/random_prober"
$: << "#{$sidecarDir}/scripts"
$: << "#{$sidecarDir}/scripts/ruby"
$: << "#{$sidecarDir}/condor"
$: << $libDir
$: << '/usr/local/lib/ruby/1.8' # really should be there by default, but isn't

require 'condorSolve.rb'

class DumpIpsFromDB
	def DumpIpsFromDB.dump
		cmd = "select distinct resp,rr from traces"
		#cmd = "select resp,rr from traces limit 100"		# debug
		ips=Hash.new
		PsqlHack.select(cmd) { |line|
			tokens=line.strip.split(/\s*\|\s*/)
			ips[tokens[0]]=1	# icmp response
			if tokens[1]
				tokens[1].gsub(/[\s{}]*/,'').split(/,/).each { |rr|
					ips[rr]=1
				}
			end
		}
		ips.each_key { |ip|
			puts ip if ip
		}
	end
end

if __FILE__ == $0
	DumpIpsFromDB.dump
end

