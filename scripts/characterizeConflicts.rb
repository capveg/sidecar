#!/usr/bin/ruby

$sidecarDir=ENV['SIDECARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"

############## TODO
# 1) Don't send probes to a vantage point that are local to that vantage point
# 2) Clean up vantagepoint testing when there are filtered packets
# 3) make a bunch of the pcap overload messages parsed errors and maybe count them


$: << "#{$sidecarDir}/random_prober"
$: << "#{$sidecarDir}/scripts"
$: << $libDir
$: << '/usr/local/lib/ruby/1.8' # really should be there by default, but isn't


require 'progressbar_mixin'

class CharConflicts
	#include ProgressBar_Mixin
	def initialize(file)
		@rrend=0
		@notRRend=0
		@file=file
		@dir=File.dirname(file)
	end
	def characterizeFile
		File.open(@file,"r").each { |line|
			characterize(line)
		}
	end
	def characterize(line)
		# line = 'link(ip213_248_80_244,ip213_248_86_49,1) 3 \
		#	alias(ip213_248_80_244,ip213_248_86_49) 1  \
		#	(./129/12/64/151/clique-129.12.3.75-64.151.112.20.model; \
		#	/128/232/64/151/clique-128.232.103.201-64.151.112.20.model; \
		#	./128/232/64/151/clique-128.232.103.203-64.151.112.20.model) \
		#	(./129/12/64/151/clique-129.12.3.74-64.151.112.20.model)'
		tokens=line.split
		ips=tokens[0].split(/[(,)]/)
		linkBelievers = tokens[4].split(/[();]/)
		aliasBelievers = tokens[5].split(/[();]/)
		linkBelievers.shift if linkBelievers[0] =~ /^\s*$/
		aliasBelievers.shift if aliasBelievers[0] =~ /^\s*$/
		ip1 = ips[1].sub(/^ip/,'').gsub(/_/,'.')
		ip2 = ips[2].sub(/^ip/,'').gsub(/_/,'.')
		linkRRend=countRRend(ips[1],ips[2],linkBelievers)
		aliasRRend=countRRend(ips[1],ips[2],aliasBelievers)
		linkPercent = (100.0*linkRRend)/linkBelievers.size
		aliasPercent = (100.0*aliasRRend)/aliasBelievers.size
		if linkPercent > aliasPercent
			certainty = linkPercent/(aliasPercent==0.0? 0.001: aliasPercent )
		else
			certainty = aliasPercent/(linkPercent==0.0? 0.001: linkPercent )
		end
		puts "#{ip1} #{ip2}  | #{certainty} | rr_link #{linkPercent}  #{linkBelievers.size} ||| rr_alias #{aliasPercent} #{aliasBelievers.size}"
	end
	def countRRend(ip1,ip2,files)
		count=0
		# match other(ip206_57_40_233,rrend) for either ip
		pattern = Regexp.compile("other\\((#{ip1}|#{ip2}),rrend\\)")
		files.each { |f|
			foundRRend=false
			File.open(@dir + '/' + f,"r").each { |line|
				line.split.each { |fact|
					foundRRend=true if fact =~ pattern
				}
			}
			count+=1 if foundRRend
		}
		return count
	end
end


if $0 == __FILE__
	CharConflicts.new(ARGV[0]).characterizeFile
end
