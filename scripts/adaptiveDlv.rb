#!/usr/bin/ruby


$sidecarDir=ENV['SIDECARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"



$: << "#{$sidecarDir}/random_prober"
$: << "#{$sidecarDir}/scripts"
$: << $libDir
$: << '/usr/local/lib/ruby/1.8'	# really should be there by default, but isn't
#begin
#	require 'dbi'   # install from http://rubyforge.org/projects/ruby-dbi/; see notes at bottom
#rescue LoadError => e
#	$stderr.puts "Need to install ruby-dbi from http://rubyforge.org/projects/ruby-dbi"
#	$stderr.puts " Read the bottom of the source of ips2ttldistance2db.rb for more info"
#	exit!
#end

$noScriptroute=true
require 'nspring-utils'
require 'fprogressbar'
#require 'ips2ttldistance2db.rb'
require 'cvtimeout'



class AdaptiveDlv
	attr_writer :timeout
	def initialize(file,fatal=false,timeout=1,multiplier=5)	# multiplier <=2 is too short for 059-combitest-all-opposite.test
		@file=file
		@fatal=fatal
		@timeout=timeout
		@lastTimeoutPerPair=timeout
		@timeoutMin=calcTimeoutMin
		@testfactsCmd='test-facts.sh'
		@timeoutMultiplier=multiplier
		@troubleProbePairs=Hash.new
		@probePairs = Hash.new
	end

	def calcTimeoutMin	# the min is the time to solve non-RR probe pairs
		count=0
		File.open(@file,"r").each { |line|
			count+=1 if /^trPair/.match(line)
		}
		return [count/10,10].max
	end

	
	def testSolve(file,timeout=@timeout)
		base = file.sub(/\.dlv$/,'')
		cmd = "#{@testfactsCmd} #{file} "
		orignalstdout=$stdout
		outfile=File.open(base+".model","w+")
		$stdout.reopen(outfile)		# redirect stdout to "base.mode"
						# do it here instead of in "cmd"
						# b/c this will keep the exec'd process in
						# the same pid for ease of kill'ing
		if ! Kernel.system_with_timeout(timeout,cmd)
			raise "Kernel.system command '#{cmd}' interrupted"
		end
		if Kernel.test(?s,base + ".model")
			return 0		# success
		else
			#$stderr.puts "Error: #{file} produced an empty model"
			return 1
		end
		rescue Timeout::Error => e
			# since we got a timeout, split the probe pairs and try again
			#$stderr.puts "Error: #{file} timed out before it could produce a model"
			return 2
		ensure
			outfile.close
			$stdout.reopen(orignalstdout)	
	end	
	def appendSuffix(suffix="")
		if ( /\.dlv$/.match(@file))
			@file.sub(/\.dlv$/,suffix+".dlv")
		else
			@file + suffix + ".dlv"
		end
	end
	def solve(startTTL=nil) 
		@probePairs, @maxTTL = getProbePairsByTTL	# get a list of all probe pairs
		if startTTL==nil 
			# if it works right off the bat, just return happily
			initTTL=0
			if testSolve(@file,calcTimeout(countProbePairs(@maxTTL))) == 0	
				return 0
			elsif @fatal
				return 1
			else
				$stderr.puts "Simple test failed; going to adaptive mode"
			end
		else
			initTTL=startTTL.to_i
			$stderr.puts "Skipping simple test; going directly to adaptive mode at ttl=#{initTTL}"
		end
		raise "No Probe Pairs found" unless @probePairs.size >0
		timeoutEstimate=@timeout
		(initTTL..@maxTTL).each { |step|		
			# foreach probe pair set, make a new copy of the dlv that only includes
			# 	probepairs from TTL <= step
			badProbes = divideAndConquer(step) # test this subset of probePairs
			if badProbes.size != 0
				$stderr.puts "Divide and conquer partial success -- ignoring #{badProbes.size} new probePairs"
				badProbes.keys.each { |k|
					@troubleProbePairs[k]=1;
				}
			end
		}
		if (@troubleProbePairs.size == 0)
			$stderr.puts "Weird: was able to solve #{@file} w.o timeout the 2ndtime but not the first"
		else
			$stderr.puts "Able to solve #{@file} removing #{@troubleProbePairs.size} probe pairs"
			@troubleProbePairs.keys.each { |line|
				$stderr.puts "BAD: " + line.chomp
			}
		end

	end
	def createTestDlv(out,ttl,start,stop,filter=nil) 	# create a tmp dlv file with all probe pairs with step<=ttl
							# but skipping any probePair in filter or in @troubleProbePair
		makeCopy(@file,out)	# copy the existing dlv file, sans probePairs
		File.open(out,"a") { |f|
			(0...ttl).each { |step|	# copy in the probePairs for step<ttl
				f.puts "% Lines from ttl=#{step}"
				next unless @probePairs[step]
				@probePairs[step].each { |line|
					# print it, unless we've previously marked it as trouble
					f.puts line	unless  @troubleProbePairs[line] || ( filter && filter.has_key?(line))
				}
			}
			# next add the specific subset for ttl=ttl, from indexes [start..stop]
			f.puts "% Lines from step=#{ttl}"
			next unless @probePairs[ttl]
			@probePairs[ttl][start..stop].each { |line|
				# print it, unless we've previously marked it as trouble
				f.puts line	unless  @troubleProbePairs[line] || ( filter && filter[line])
			}
		}
	end
	def countProbePairs(ttl)
		c=0
		(0..ttl).each { |i|
			@probePairs[i].each { |probePair|
				c+=1 unless /^% /.match(probePair) 	# looks like the syntax highlighter can't deal with regexps with %
			}
		}
		c
	end
	def calcTimeout(nPairs)
		nPairs*@lastTimeoutPerPair*@timeoutMultiplier+@timeoutMin	# nspring's formula
	end
	def divideAndConquer(ttl,start=nil,stop=nil,filter=nil,level="-")
		start=0 unless start
		stop=@probePairs[ttl].size-1 unless stop
		filter=Hash.new unless filter
		raise "Bad start=#{start},stop=#{stop} values in divideAndConquer(#{@probePairs[ttl].size})" if stop<start || 
						start<0 || start >= @probePairs[ttl].size
		out = appendSuffix("-#{ttl}#{level}")
		createTestDlv(out,ttl,start,stop,filter)	# create a tmp dlv file with all probe pairs in rawith ttl<step and all ttl [start..stop]
			#@startTime = Time.now
			#@ellapsed=Time.now-@startTime
			#$stderr.puts "		ellapsed time " + @ellapsed.to_f.to_s
			#timeoutEstimate=@timeoutMultiplier*@ellapsed.to_f	# guess the time for ttl+1 to be atmost x@timeoutMultiplier ttl's time
		#timeout=@lastTTLTime*@timeoutMultiplier
		nPairs = countProbePairs(ttl)
		timeout=calcTimeout(nPairs)
		$stderr.puts "Adaptive Test ttl=#{ttl}/#{@maxTTL} out=#{out} level=#{level} #{timeout} seconds"
		startTime=Time.now
		success =  testSolve(out,timeout) ==0
		ellapsedTime = (Time.now-startTime).to_f
		$stderr.puts 	"		Runtime #{ellapsedTime.to_s} nPairs= #{countProbePairs(ttl)}"
		if success 		# add addaptive timeout here
			@lastTimeoutPerPair=ellapsedTime/nPairs if nPairs>0
			return filter	# return the list of filter elements that allowed us to pass
		elsif start == stop
			# we were only given one probePair to test and it failed
			$stderr.puts "	Found potential bad probe pair ttl=#{ttl} entry=#{start}: #{@probePairs[ttl][start]}"
			$stderr.puts "	Verifying that the model works without this probepair"
			filter[@probePairs[ttl][start]]=1
			# create another test file *without* this probe pair
			createTestDlv(out,ttl,start,stop,filter)
			if testSolve(out)	# and test again
				return filter	# test succeeded without this probe pair; 
							# model is good; return this probepair in the good filter
			else
				raise 	"Bad model: ttl=#{ttl} level=#{level} nProbePairs=#{@ProbePairs.size}\n" +
					"	unable to converge with and without probe pair #{start}  \n" + 
					@probePairs.keys.each_index{ |i| "#{i}: #{@probePairs[@ProbePairs.keys[i]]}\n"}.join
			end
		else
			# else we have to divide and recursively search for the bad probePair
			middle=((stop-start)/2.0).ceil
			$stderr.puts "Solver failed to find a valid model: Recursing(#{@probePairs[ttl].size})  level=#{level} recursing on probes [#{start},#{start+middle-1}]" 
			filter_left = divideAndConquer(ttl,start,start+middle-1,filter,level+"0")
			$stderr.puts "					   level=#{level} recursing on probes [#{start+middle},#{stop}]"
			filter_right = divideAndConquer(ttl,start+middle,stop,filter_left,level+"1")
			$stderr.puts "Now trying to join probes [#{start},#{start+middle-1}] with [#{start+middle},#{stop}] with new filter"
			out = appendSuffix("-#{ttl}#{level}-join")
			createTestDlv(out,ttl,start,stop,filter_right)
			startTime=Time.now
			success =  testSolve(out,timeout) ==0
			ellapsedTime = (Time.now-startTime).to_f
			$stderr.puts 	"		Runtime #{ellapsedTime.to_s}"
			if success 		# add addaptive timeout here
				@lastTTLTime=ellapsedTime
				$stderr.puts "Successful join: continuing... "
				return filter_right	# return the list of filter elements that allowed us to pass
			else
				$stderr.puts " Join failed.. complicated bad model"
				raise "Complicated Model"
			end
		end
	end
	def makeCopy(src,dst)
		Kernel.system("grep -v ^potentialProbePair #{src} | grep -v ^gap > #{dst}")
	end
	def getProbePairsByTTL
		id2ttl = Hash.new
		probePairList = Hash.new
		File.open(@file,"r").each { |line|
			# potentialProbePair(ip128_223_8_112_1,ip128_223_8_112_2,0,0).
			if line =~ /^potentialProbePair\((ip[\d_]+),(ip[\d_]+),\d+,\d+\)/
				probePairList[$2] = "" unless probePairList[$2]
				probePairList[$2] += line
			elsif line =~ /^gap\((ip[\d_]+),(ip[\d_]+),\d+,\d+,\d+\)/
				probePairList[$2] = "" unless probePairList[$2]
				probePairList[$2] += line 
			# tr(ip128_223_8_112_13,ip128_223_8_112,7,ip205_189_32_193,1).
			elsif line =~ /^tr\((ip[\d_]+),ip[\d_]+,(\d+),ip[\d_]+\,\d+\)/
				id2ttl[$1]=$2.to_i
			end
		}
		ret = Hash.new
		probePairList.each { |id,probePair|
			if id2ttl.has_key?(id)
				ret[id2ttl[id]] = Array.new unless ret[id2ttl[id]]
				ret[id2ttl[id]] << probePair
			else
				$stderr.puts "Id #{id} not found in id2ttl: aborting"
				raise "Badness"
			end
		}
		(0..id2ttl.values.max).each { |i|	# ensure that all ttl's have a valid entry
			ret[i]=Array["% No probePairs for ttl=#{i}" ] unless ret[i]	# even if it's just empty
		}
		return ret,id2ttl.values.max
	end

end

if $0 == __FILE__
	Thread.abort_on_exception = true        # to avoid threads silently dying
	$stderr.sync=true       # this should be redundant, but isn't
	fatal=false
	if ARGV[0] && ARGV[0]== '-f'
		fatal=true
		ARGV.shift
	end
	trap("SIGINT") {
		$stderr.puts "Caught SIGINT -- exiting"
		exit1(0)
	}
	AdaptiveDlv.new(ARGV[0],fatal).solve(ARGV[1])
end
