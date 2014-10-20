#!/usr/bin/ruby
# 	usage: calc-ipdistance.rb foo.adj table
#       1) takes an adj file and DB table name
#       2) foreach link in foo.adj
#		look up the ips of endpoints, calc their distance
#		and print

UsageString='usage: calc-ipdistance.rb table [-adj foo.adj| -pairs thresholddistance | -rand k_times | -randThresh k max_thresh]'

$sidecarDir=ENV['SIDCARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"
$: << "#{$sidecarDir}/random_prober"
$: << $libDir


require 'ips2ttldistance2db.rb'	# includes require dbi code 
require 'progressbar.rb'

class File
	def each_progress(str,outfile=$stderr)
		# "12345 file\n" --> 12345
		nLines=Kernel.open("|wc -l #{self.path}").gets.split[0].chomp.to_i
		#$stderr.puts "Got #{nLines} for #{self.path}"
		pb = ProgressBar.new(str,nLines,outfile)
		pb.set(0)
		self.each { |line|
			yield line
			pb.inc
		}
	end
end



class IpDistance
	attr_accessor :minThreshold
	def initialize(tablename)
		@ip2db=Ips2TTLdistance2db.new
		@tablename=tablename
		@dbh = DBI.connect("DBI:Pg:dbname=#{@ip2db.databasename};host=#{@ip2db.databasehost}", @ip2db.databaseuser, @ip2db.databasepasswd)
		@minThreshold=-255	# by default, list everything
	end
	def allIps
		if(!@allIps)
			$stderr.puts "Making list of all Ips in #{@tablename}"
		 	@allIps= @dbh.select_all("SELECT distinct ip from #{@tablename}") 
			$stderr.puts "#{@allIps.length} Ips found in  #{@tablename}"
		end
		@allIps
	end

	def processAdj(file,minThreshold=@minThreshold)
		File.open(file).each_progress("Adj"){ |line|
			# Link  R10_A:206.196.177.126 -- R14_B:206.196.177.125 : RR
			if(line =~ /^Link\s+[^:]+:([\d.]+)\s+--\s+[^:]+:([\d.]+)/)	# skip everything that doesn't begin with "Link"
				ip1=$1
				ip2=$2
				if( ip1 == ip2 )
					$stderr.puts "Skipping bogus selflink #{ip1} -- #{ip2}"
				else
					d,n = calcIpDistance(ip1,ip2)
					if( n>=minThreshold)
						if block_given?
							yield ip1,ip2,d,n
						else
							puts "#{d} #{ip1} #{ip2} #{n}"
						end
					end
				end
			end
		}
	end

	def pickRandPairs(k,minThreshold=@minThreshold)
		$stderr.puts "#{Time.now}"
		k.times { |i|
			$stderr.puts "#{Time.now}"
			ip1=allIps[Kernel.rand(allIps.length)]
			ip2=allIps[Kernel.rand(allIps.length)-1]		# this insures ip1!=ip2
			ip2=allIps[allIps.length-1] if ip1 == ip2		# while staying totally random
			d,n = calcIpDistance(ip1,ip2)
			if(n>=minThreshold)
				if block_given?
					yield ip1,ip2,d,n
				else
					puts "#{d} #{ip1} #{ip2} #{n}"
				end
			end
		}
		$stderr.puts "#{Time.now}"
	end

	def getAllPairs(maxDistance=-1.0,outfile=$stderr)
		$stderr.puts "AllPairs maxDistance=#{maxDistance}"
		pb = ProgressBar.new("AllPairs",allIps.length*allIps.length,outfile)
		pb.set(0)
		allIps.each{ |ip1|
			cord1 = getIpCord(ip1)
			allIps.each{ |ip2|
				if( ip1.to_s < ip2.to_s) then
					d,n = calcIpDistance(ip1,ip2,cord1)	# pass on/cache the value of the first cord
					if((d>=0)&&(d<=maxDistance)) then
						if block_given? then
							yield ip1,ip2,d,n
						else
							puts "#{ip1} #{ip2} #{d} #{n}"
						end
					end
				end
				pb.inc
			}
		}
	end

	def calcIpDistance(ip1,ip2,cord1=nil,cord2=nil)
		cord1 = getIpCord(ip1) unless cord1	# let the caller specify the cords if known
		cord2 = getIpCord(ip2) unless cord2	# let the caller specify the cords if known
		#$stderr.puts "#{ip1}=#{cord1}"
		#$stderr.puts "#{ip2}=#{cord2}"
		count=0.0
		sum=0.0
		cord1.each { |key,value|
			if cord2[key]
				count+=1
				sum+= (cord2[key]-cord1[key]).abs
			end
		}
		return [((count>0) ?(sum/count):-1.0),count]
	end

	def getIpCord(ip)
		cord = Hash.new
		# get the list of the most recent,valid responses from all vantages for this ip
		@dbh.select_all("SELECT vantage,ip,udp,udpr,tcp,tcpr,icmp,icmpr from #{@tablename} where " +  
				" ip='#{ip}' and ts in " +
				" (select max(ts) from #{@tablename} where ip='#{ip}' and " +
					" ( (udp>=0 and udpr='-') or " + 
					" (tcp>=0 and tcpr='-') or " +
					" (icmp>=0 and icmpr='-') )" +
					" group by vantage,ip)" ) { |r|
			row=r.to_h
			#$stderr.puts "Read row #{row['vantage']}::#{row['ip']}"

			udp=row['udp']
			tcp=row['tcp']
			icmp=row['icmp']
			udpr=row['udpr']
			tcpr=row['tcpr']
			icmpr=row['icmpr']
			d=-1
			# prefer udp cords over icmp cords over tcp cords, but take what is available
			d = tcp.to_i if (tcp and tcpr == "-" and tcp.to_i>0)		
			d = icmp.to_i if (icmp and icmpr == "-" and icmp.to_i>0)
			d = udp.to_i if (udp and udpr == "-" and udp.to_i>0)
			# map ttl's into [0:64] to avoid bad comparisons between startttl=255 and startttl=64 routers
			d-=192 if d>192 	# if start ttl=255, map down to [0:64]
			d-=64 if d>64		# if start ttl=128, map down to [0:64]
					
			cord[row['vantage']]=d
		}
		return cord
	end
	def pickRandPairsManyThresholds(k,maxThresh)
		filenameBase= "#{@tablename}.rand#{k}.thresh="
		maxThresh.downto(0){ |t|
			$stderr.puts "picking #{k} pairs with thresh #{t}"
			File.open(filenameBase+t.to_s,"w+") { |f|
				pickRandPairs(k,t) { |ip1,ip2,d,n|
					f.puts "#{d} #{ip1} #{ip2} #{n}"
				}
			}
		}
	end
end # end of class IpDistance

if __FILE__ == $0
	raise UsageString + " : needs to specify DB table name" unless ARGV[0]
	raise UsageString + " : needs to specify invocation type (-adj,-rand,etc)" unless ARGV[1]
	ipd = IpDistance.new(ARGV[0])
	case ARGV[1]
		when '-adj'
			raise UsageString + " : need to specify adj file" unless ARGV[2]
			ipd.processAdj(ARGV[2]) 
		when '-ip'
			raise UsageString + " : need to specify first ip" unless ARGV[2]
			raise UsageString + " : need to specify second ip" unless ARGV[3]
			d,n= ipd.calcIpDistance(ARGV[2],ARGV[3])
			puts "#{ARGV[2]} #{ARGV[3]} :: #{d}	from #{n} common vantages"
		when '-rand'
			raise UsageString + " : need to specify number of random pairs" unless ARGV[2]
			ipd.pickRandPairs(ARGV[2].to_i)
		when '-pairs'
			raise UsageString + " : need to specify threshold distance between pairs" unless ARGV[2]
			ipd.getAllPairs(ARGV[2].to_f)
		when '-randThresh'
			raise UsageString + " : need to specify number of random pairs" unless ARGV[2]
			raise UsageString + " : need to specify max threshold" unless ARGV[3]
			ipd.pickRandPairsManyThresholds(ARGV[2].to_i,ARGV[3].to_i)
		else 
			raise UsageString + " : unknown invocation type (#{ARGV[1]})"
	end
end
	
