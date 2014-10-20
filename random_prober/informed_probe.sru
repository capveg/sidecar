#!/usr/bin/ruby 
#require 'debug'



# grrr
[ "/usr/lib/site_ruby/1.8",
	"/usr/lib/site_ruby/1.8/i386-linux-gnu",
	"/usr/lib/site_ruby",
	"/usr/lib/ruby/1.8",
	"/usr/lib/ruby/1.8/i386-linux-gnu",
	"#{ENV['HOME']}/swork/sidecar/scripts",
	".",
	".."].each{ |p|
        $: << p
}




require 'nspring-utils'
require 'capveg-utils'
require 'workers'
require 'packets'		# copied from scriptroute
require 'socket'		# for getlocalip()
require 'timeout'		# for timeout library
#require 'benchmark'

IPOPT_EOL = 0	# should eventually end up in scriproute code
IPOPT_NOOP = 1
class EndOfLine_option < IPoption_base
	@@creators[IPOPT_NOOP] = lambda { |hdr|	# hack in NOOP support as well
		p = EndOfLine_option.new(hdr)
	}
	@@creators[IPOPT_EOL] = lambda { |hdr|
		p = EndOfLine_option.new(hdr)
	}
	def initialize(flag_or_str)
		if(flag_or_str.is_a?(Fixnum)) then
			super(IPOPT_EOL, 0, 1,nil) # maximum length is 40, but tcpdump whines.
		else
			#ipt_code = flag_or_str.unpack("c");
			#super( flag_or_str )
		    	@ipt_code = flag_or_str.unpack("c")
			@ipt_len=1
		end
	end
	def to_s 
		":ip_option_code=#{@ipt_code}"
	end
	def marshal
		@ipt_code.pack("c")  # oflw will be init'd to zero
	end
end

class MyExcpt < Exception
	def MyExcpt.excpt(*all)		# "alias :MyExcpt.exception :MyExcpt.excpt" didn't work :-(
		MyExcpt.exception(*all)
	end 
end

class TargetIp < Hash
end
class Hash1 < Hash
end
class Hash2 < Hash
end
class Hash3 < Hash
end

class Array1 < Array
end

class LockingHash 		# I am certain that ruby has a better way of doing this
	def initialize
		@h = Hash.new
		@lock = Mutex.new
	end
	def add(data)
		@lock.syncronize {
			@h[data]=1
		}
	end
	def del(data)	
		@lock.syncronize {
			@h.delete(data)
		}
	end
	def count
		@lock.syncronize {
			@h.size
		}
	end
end
		


# take a file with a list of ips as input
# two modes:

# mode 1: 	genStopList mode	(for non-planetlab)
#	foreach ip 
#		send small number (single) packets to it to find out if it is alive
#			if dead, print and continue
#		do nice traceroute+rr things to endhost, irrelevant of abuse reports
#			record all info, but particularly the last StopDistance hops
#		output "ip stop1 stop2 stop3 (..)" listing the ips of the last StopDistance hops

# mode 2: 	useStopList mode	(for planetlab)
#	require stoplist from mode 1
#	foreach ip
#		do a nice trceroute+rr to endhost *BUT* stop if you hit an IP stop_i in
#			stoplist

# default params
Debug=0
#Debug=1023
DefaultTTL=255
StopDistance=3
MaxAliveProbes=1
MaxTraceProbesPerHop=1
MaxTotalProbes=6
MaxConsecutiveBadResponses=2
NumThreads=50
ProbeSize=40
#FilterCmd="| filter_blacklist random_probe.blacklist"
FilterCmd=""	# do the filtering elsewhere
AvgBandwidthBPS=10*1024	# 20KB/s 
PacketDelayTime=5.0	# we should prob read this delay from scriptroute; but dunno/doncare how
MaxPacketsPerTrain=AvgBandwidthBPS*2*PacketDelayTime/(ProbeSize*NumThreads)	 # "*2" b/c the timeout is from the last packet sent
MinPacketsPerTrain=1
MaxQueueSize=MaxPacketsPerTrain*NumThreads	# to prevent our mem foot print from getting too big
MinQueueSize=MaxPacketsPerTrain*2		# to make sure there is always some data avail for threads
MaxIterations=8
ScriptrouteErrorPause=10			# when scriptrouted gives us an err, sleep this many seconds
TooManyRetries=5
$verbose=nil
#$verbose=1

$trackIPMode=false



# constants
ModeGen="Generate StopList"
ModeUse="Use StopList"

ModeGen_NeedAliveTest=0
ModeGen_DoingAliveTest=1
ModeGen_Dead=2
ModeGen_Tracing=3
ModeGen_Stopped=4
ModeGen_Done=5
ModeGen_OutOfProbes=6
ModeGen_Abort=7

ModeUse_RRTrace=100
ModeUse_Done=101
ModeUse_Unreach=102
ModeUse_UnknownICMP=103
ModeUse_UnknownProto=104
ModeUse_TooManyBadResponses=105
ModeUse_NeedInit=106
ModeUse_Abort=7
ModeUse_TooManyRetries=108
ModeUse_Corruptstate=109

# global(s)
$mode=nil
###################################################################

def usage(str1=nil,str2=nil)
	if str1
		$stderr.puts "#{str1}"
	end
	if str2
		$stderr.puts "#{str2}"
	end

	$stderr.puts "usage: random_prober.sru [-v] [-f] <-genStopList|-useStopList> iplist"
	exit 1
end


#################################################################
def doModeGen(inputFileName)
	ipQ = Queue.new
	iplist=Array.new
	threadList=Array.new
	if ! File.stat(inputFileName)
		$stderr.puts "File '#{inputFileName}': $!"
	end
	nIPs = `wc -l #{inputFileName}`.split[0].to_i
	$stderr.puts "File #{inputFileName} has #{nIPs} IPs; randomizing"
	if ! Kernel::test(?s, "#{inputFileName}.randomized")
		raise MyExcpt.excpt("we should have been randomzied by now")
	end
	$outputfile= File.open("#{inputFileName}.stoplist",File::CREAT|File::RDWR)
	inputFile= File.new("#{inputFileName}.randomized")
	inputFile.each { |line|
		line.chomp!
		ip=Hash.new
		ip[:state]=ModeGen_NeedAliveTest
		ip[:ip]=line
		modeGenUpdatePacket(ipQ,ip,nil)
		if ipQ.size >= MaxQueueSize
			break		# don't read more then the q size; HACK
		end
	}
	# setup some shared variables
	workers = Workers.new(NumThreads+1)
	readcond = ConditionVariable.new
	readlock= Mutex.new
	$progressbar=ProgressBar.new("IPs finished",nIPs)
	$progressbar.set(0)
	# spawn off NumThread new threads
	$stderr.puts "Spawning #{NumThreads} threads: MaxQueueSize=#{MaxQueueSize}"
	readlock.synchronize {
		# now read the rest of the threads
		workers.startWorking(Thread.current[:index])
		NumThreads.times { |threadId|
			threadList << Thread.new(threadId) { |id|
				Thread.current["index"]=id
				packetConsumer(ipQ,workers,readlock,readcond,:modeGenUpdatePacket)
				$stderr.puts "Thread #{threadId} exiting"
			}
		}
		sleep(10) if Debug>0
		inputFile.each { |line|
			while(ipQ.size>= MaxQueueSize)	# wait for threads to signal the queue is not full
				$stderr.puts "Producer thread sleeping: #{ipQ.size} ips on queue" 
				begin 
					readcond.wait(readlock)	
				#rescue ThreadError => e 
				rescue Exception => e 
					$stderr.puts "Got a thread error: checking condition of existing threads"
					threadList.each { |thread|	# go through each thread and print it's status
						stat=thread.status
						if stat
							$stderr.puts "T #{thread[:index]} #{stat}"
						else
							$stderr.puts "T #{thread[:index]} returned status nil!"
						end
					}
					$stderr.puts e
				end
			end
			line.chomp!
			ip=Hash.new
			ip[:ip]=line
			ip[:state]=ModeGen_NeedAliveTest
			modeGenUpdatePacket(ipQ,ip,nil)
			readcond.broadcast()		# tell ppl there is new stuff in the queue
		}
		workers.stopWorking(Thread.current[:index])		# signal that no more work is coming from this thread
		readcond.broadcast()		# tell ppl to check to see if there is any more work to be done
	}
	$stderr.puts "Done spooling new IPs; waiting for threads to finish"
	
	# wait for threads to finish
	threadList.each { |thread|
		thread.join
	}
end
##################################################################
def printGenFinishedIP(ip)
	# now dump the contents
	$progressbar.inc unless ($verbose||Debug!=0)
	case ip[:state]
	when ModeGen_Done then
		$outputfile.puts "DONE: #{ip[:ip]} : #{ip[:stopList].join(' ')}"
	when ModeGen_Stopped then 
		$outputfile.puts "STOPPED: #{ip[:ip]} : #{ip[:stopList].join(' ')}"
	when ModeGen_Abort then 
		$outputfile.puts "ABORT: #{ip[:ip]} : #{ip[:stopList].join(' ')}"
	when ModeGen_OutOfProbes then 
		$outputfile.puts "OUTOFPROBES: #{ip[:ip]} : #{ip[:stopList].join(' ')}"
	when ModeGen_Dead then
		$outputfile.puts "DEAD: #{ip[:ip]}"
	when ModeGen_NeedAliveTest,ModeGen_DoingAliveTest,ModeGen_Tracing then
		raise MyExcpt.excpt("Ended program with state #{ip[:state]} for #{ip}")
	else
		raise MyExcpt.excpt("Unknown state #{ip[:state]} for #{ip}")
	end
end
#################################################################
def printUseFinishedIP(ip)
	$progressbar.inc unless ($verbose||Debug!=0)
	File.open("data-%s,0-%s,33434" % [ $localip,ip[:ip]],"w") { |out|
		out.puts "# finalstate #{ip[:ip]}==#{ip[:state]}"
		out.puts "# stoplist = #{ip[:stopList].join(' ')}"
		# "TTL X it=Y"; sort by Y, then X
		ip[:data].keys.sort{|a,b| 
				c=a.split; d=b.split; 
				c[2].sub!(/it=/,'')
				d[2].sub!(/it=/,'')
				res = c[2].to_i <=> d[2].to_i 
				res = c[1].to_i <=> d[1].to_i if res == 0 
				res }.each  { |key|
			out.puts "- RECV #{key} from #{ip[:data][key]}"
			ip[:data][key]=nil	# to duck memory leak(?)

		}
		$trackIP.del(ip[:ip]) if $trackIPMode
		ip[:data]=nil	# to duck memory leak(?)
		out.close
	}
end
#- RECV TTL 2 it=0 from   140.142.155.23 (254)   ROUTER   rtt=0.000819 s t=1147905261.893402 RR, hop 1 140.142.155.15 ,  Macro

#################################################################
## This proc reads some number of ips off the ip queue, sends associated packets,
#	updates their state, potentially generating new packets on the queue
def packetConsumer(ipQ,workers,readlock, readcond,updateFunction)
	# wait for packetsInTrain things to show up at once
	raise MyExcpt.excpt("Bad queue") unless ipQ
	while true
		$stderr.puts "	packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]}" if $verbose
		# randomizing the number of packets in a train just doesn't seem useful -- nevermind
		#packetsInTrain = rand(MaxPacketsPerTrain-MinPacketsPerTrain)+MinPacketsPerTrain
		packetsInTrain = MaxPacketsPerTrain.to_i 
		ipBuffer= nil
		# block1 = Benchmark.measure do 
		readlock.synchronize{
			$stderr.puts "	packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]}: " + 
				" got readlock" if $verbose
			# wait for stuff to be available or people to claim their not making anymore
			while ipQ.empty? 
				$stderr.puts "	packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]}: " + 
					" empty queue " if $verbose
				if !workers.inProgress?
					$stderr.puts "EXITING1: packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]} w=#{workers.nWorking?}" if $verbose
					readcond.signal	# tell someone else to wake up; it's time for them to die as well
					return
				else
					$stderr.puts "	packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]}: " + 
						"sleeping on empty queue" if $verbose
					readcond.wait(readlock)
				end
			end
			$stderr.puts "	packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]}: " + 
				" about to grab #{packetsInTrain} packets off queue" if $verbose
			raise MyExcpt.excpt("Empty packet Q (weird): - T# #{Thread.current[:index]}") if ipQ.empty?
			ipBuffer = ipQ.pop_upto_n(packetsInTrain)
			$stderr.puts "	packetConsumer #{__FILE__}:#{__LINE__} - T# #{Thread.current[:index]}: " + 
				"grabbed #{ipBuffer.length} packets off queue" if $verbose
			raise MyExcpt.excpt("Empty ip Buffer (weird): - T# #{Thread.current[:index]}") if ipBuffer.empty?
			workers.startWorking(Thread.current[:index])   # flag this thread as doing something
		}
		# end
		# $stderr.puts "T# #{Thread.current[:index]} block1 #{block1.to_s} "
		raise MyExcpt.excpt("Empty ip Buffer (weirdER): - T# #{Thread.current[:index]}") if ipBuffer.empty?
		# now we actually send a whole bunch of stuff
		#delayinc = PacketDelayTime/ipBuffer.size
		delayinc = 0	# delayinc = 0 b/c we're worried that we're working the packetsheduler too hard - pcap overload
		#raise "delayinc too small: #{delayinc}" if delayinc <0.001
		begin
			packetTrain = Array.new
			ipBuffer.each { |ip|		# don't use ipBuffer.map, b/c packetTrain.length<=ipBuffer.length
				raise MyExcpt.excpt("Bad iphash==nil") unless ip
				if ip[:nextPacket]
					if $fakeMode
						packetTrain << mkProbeWrapper(ip)
					else
						tmp = Struct::DelayedPacket.new(delayinc,mkProbeWrapper(ip))
						packetTrain << tmp if tmp
					end
				else
					$stderr.puts "BAD: Ignoring IP #{ip[:ip]} with nil nextPacket field"
				end
			}
			raise MyExcpt.excpt("Empty packet train (weird): - T# #{Thread.current[:index]}:"+
				" nIPs=#{ipBuffer.size}") if packetTrain.empty?
			$stderr.puts " Sending #{packetTrain.length} packetTrain: - T# #{Thread.current[:index]} workers=#{workers.nWorking?}" if Debug&8==8
			resp = ()
			#timeout(PacketDelayTime*1200) {
				#block2 = Benchmark.measure {
					resp = Scriptroute::send_train(packetTrain)			
				#}
				# $stderr.puts "T# #{Thread.current[:index]} block2 #{block2.to_s}"
			#}
			$stderr.puts " Processing #{resp.length} packetTrain: - T# #{Thread.current[:index]} workers=#{workers.nWorking?}" if Debug&8==8
			# block3 =Benchmark.measure do 
			readlock.synchronize { 	# to put IPs back on the queue
				resp.each_with_index { |r,i|
					# for each response, good/bad/timeout/whathaveyou, pass to updateFunc to decide what next
					if r 
						Object.method(updateFunction).call(ipQ,ipBuffer[i],r)	# this will queue the next packet
					else
						# if we got here, we didn't even get a valid response and
						# the scriptroute daemon is probably over worked
						#  - requeue and try again
						if ipBuffer[i][:retrycount]
							ipBuffer[i][:retrycount]+=1
						else
							ipBuffer[i][:retrycount]=1
						end
						if ipBuffer[i][:retrycount] > TooManyRetries
							$stderr.puts "Too many retries on #{ipBuffer[i][:ip]}: giving up"
							ipBuffer[i][:state]=ModeUse_TooManyRetries
							printUseFinishedIP(ipBuffer[i])
						else
							ipQ.push(ipBuffer[i])	# assume r=nil is non-fatal and just needs a requeue
						end
					end
				}
			}
			# end
			# $stderr.puts "T# #{Thread.current[:index]} block3 #{block3.to_s}"
			rescue TimeoutError => e
				$stderr.puts "Scriptroute::send_train:: T# #{Thread.current[:index]}:'#{e.to_s.chomp}': TIMEOUT; requeuing"
				ipBuffer.each{ |ip|
					ipQ.push(ip)
				}
			rescue MyExcpt => e
				raise e
			rescue Exception => e
				$stderr.puts "Scriptroute::send_train:: T# #{Thread.current[:index]}:'#{e.to_s.chomp}': splitting up chunks of %d and %d" %
							[ ipBuffer.length/2 , ipBuffer.length-(ipBuffer.length/2)]
				$stderr.puts e.backtrace 
				if ipBuffer.length ==1 
					$stderr.puts "Giving up on ip=#{ipBuffer[0][:ip]}"
					ipBuffer[0][:state]=ModeGen_Abort
					if($mode==ModeGen)
						printGenFinishedIP(ipBuffer[0])
					else
						printUseFinishedIP(ipBuffer[0])
					end
				else
					ipBuffer[0,ipBuffer.length/2].each{ |ip|
						ipQ.push(ip)
					}
					readcond.signal	# wake up one other threads
					Thread.pass		# make other ppl do work now
					sleep(ScriptrouteErrorPause)	# chill for a bit to see if scriptrouted can sort out errors
					ipBuffer[ipBuffer.length/2,ipBuffer.length-(ipBuffer.length/2)].each { |ip|
						ipQ.push(ip)	# push the rest onto other side, to mix things up
					}
				end 
			ensure 
				readlock.synchronize{
					workers.stopWorking(Thread.current[:index])
					$stderr.puts " Stopping work - T# #{Thread.current[:index]} - working=#{workers.nWorking?}" if Debug&8==8
					readcond.broadcast()		# wake everyone up that the queue had changed states
				}
		end
	end
end
	
#################################################################
def mkProbeWrapper(ip)
	if($mode==ModeGen)
		rr=false
	else
		rr = ip[:iteration]%2==1
	end
	mkProbe(ip[:ip],ip[:ttl],rr)
end
#################################################################
def mkProbe(dst,ttl=DefaultTTL,rr=false,dport=33434)
	p = TCP.new(0)
	#p = Scriptroute::Tcp.new(0)
	p.ip_dst=dst
	p.ip_ttl=ttl
	p.th_dport=dport
	p.th_seq = rand(4294967295)
	p.th_ack = rand(4294967295)
	p.th_flags = 0x10	# should be ACK flag
	p.th_win = 5840		# Linux default for MSS=1460
	#raise "Adding RR not supported yet" if rr
	if rr 
		p.add_option(RecordRoute_option.new)
	end
	#p
	if $fakeMode		# fakeMode is where we fake the Scriptroute calls for debugging
		p
	else
		# copied from ping-r.sru from SVN repo
		Scriptroute::pkt_from_string(p.marshal)	# believe this hack will make RR work;
	end
	rescue Exception => e
		$stderr.puts "Weird exception #{e.to_s}"
		raise e
end
#################################################################
# we have to guess based on the number of hops from them to us
#	and hope the paths are roughly symetric
def guessTTL(probe)	
	ttl=probe.ip_ttl
	case ttl
	when 0..64 then
		guess= 64-ttl
	when 65..128 then
		guess= 128-ttl
	else
		guess= 255-ttl
	end
	guess
end
#################################################################
# in modeGen, if we got a response for our stop list
#	decide if we need to increase or decrease our TTL to complete the stopList
#	(or if we are done)
def handleGenTraceResponse(ipQ,ip,resp)
	ip[:nextPacket]=nil
	if(!ip[:endttl])
		# we don't yet know where our last hop is
		if(resp.packet.ip_p != IPPROTO_TCP)
			# still need to find our last hop
			ip[:savedHops][ip[:ttl]]=resp.packet.ip_src	# save what we have
			ip[:ttl]+=1					# try a bit further along
			ip[:nextPacket]=true
		else
			# but we just found our last hop
			ip[:endttl]=ip[:ttl]
			# convert our saved traces into stopList entries, now that we know where to put them
			ip[:savedHops].each_pair{ |ttl,src|
				i=ip[:endttl]-ttl-1
				if i < StopDistance-1 # is it close enough to be on the StopList
					ip[:stopList][i]=src
				end
			}
			# decide if we need to do more probing
			if (ip[:stopList].size < StopDistance)
				ip[:ttl]=ip[:endttl]-ip[:stopList].size-1 #start where we are missing info
				ip[:nextPacket]=true
			end
		end
	else
		# we know where the last hop is
		i=ip[:endttl]-ip[:ttl]-1
		$stderr.puts "Got stopList #{i} for #{ip[:ip]}:: #{resp.packet.to_s}" if $verbose
		ip[:stopList][i]=resp.packet.ip_src
		if i < StopDistance-1
			# if we should send more probes to find more of the stopList
			ip[:ttl]-=1
			ip[:nextPacket]=true
		else
			# else we are done with it
			ip[:state]=ModeGen_Done
			printGenFinishedIP(ip)
		end
	end
	if ip[:nextPacket]
		ip[:probesSent]+=1
		if (ip[:probesSent] >= MaxTotalProbes)
			ip[:state]=ModeGen_OutOfProbes
			printGenFinishedIP(ip)
		else
			ipQ.push(ip)
		end
	end

end
#################################################################

def modeGenUpdatePacket(ipQ,ip,response)
	$stderr.puts "---- Entering modeGenUpdatePacket: T# #{Thread.current[:index]}" if Debug&512==512
	raise MyExcpt.excpt("Bad ip==nil") unless ip
	case ip[:state]
	when ModeGen_NeedAliveTest then
		ip[:aliveProbesLeft]=MaxAliveProbes
		ip[:traceProbesLeft]=MaxTraceProbesPerHop
		ip[:probesSent]=0
		ip[:state]=ModeGen_NeedAliveTest
		ip[:stopList]=Array.new
		ip[:savedHops]=Hash.new
		ip[:ttl]=DefaultTTL
		ip[:nextPacket]= true
		ip[:state]=ModeGen_DoingAliveTest
		ipQ.push(ip)
	when ModeGen_DoingAliveTest then
		if !response.response
			ip[:aliveProbesLeft]-=1
			if ip[:aliveProbesLeft] > 0
				# try again if we haven't tried too many times
				ip[:nextPacket]=true
				ip[:probesSent]+=1
				ipQ.push(ip)
			else 
				#puts "FAILED: #{ip[:ip]}"
				ip[:state]=ModeGen_Dead
				printGenFinishedIP(ip)
				ip[:nextPacket]=nil
			end
		else
			# got a response to our alive test
			$stderr.puts "SUCCESS: #{ip[:ip]}" if $verbose
			ip[:state]=ModeGen_Tracing
			ip[:guessttl]=guessTTL(response.response.packet)
			$stderr.puts "Guessing #{ip[:ip]} is at TTL=#{ip[:guessttl]}:: #{response.response.packet.to_s}" if $verbose
			ip[:ttl]=ip[:guessttl]	# start probing where our guess is
			ip[:nextPacket]=true
			ipQ.push(ip)
		end
	when ModeGen_Tracing then
		if !response.response
			ip[:traceProbesLeft]-=1
			if ip[:traceProbesLeft] > 0
				# try again if we haven't tried too many times
				ip[:nextPacket]=true
				ipQ.push(ip)
			else 
				#puts "FAILED: #{ip[:ip]}"
				ip[:state]=ModeGen_Stopped
				printGenFinishedIP(ip)
				ip[:nextPacket]=nil
			end
		else
			# we got a response, handler it in it's own proc
			handleGenTraceResponse(ipQ,ip,response.response)
		end
	when ModeGen_Dead,ModeGen_Stopped,ModeGen_Done,ModeGen_OutOfProbes then
		raise MyExcpt.excpt("Tried to update ip #{ip.to_s} in state #{ip[:state]}")
	else
		raise MyExcpt.excpt("Unknown state #{ip[:state]} for #{ip}")
	end
	$stderr.puts "---- Leaving modeGenUpdatePacket: T# #{Thread.current[:index]}" if Debug&512==512
	rescue Exception => e
		$stderr.puts "Got weird exception: #{e.to_s}"
		raise e
end
#################################################################
def parseRR(p)
	return nil if $fakeMode	# don't run this b.c we haven't implemented to_bytes and don't need it
	bytes= p.to_bytes
	parsedOptions=nil
	case p.ip_p 
	when IPPROTO_ICMP then
		offset=(p.ip_hl*4)+8
	when IPPROTO_TCP,IPPROTO_UDP then
		offset=0		# try to find RR in the TCP/UDP packets, even if unlikely
	else
		raise MyExcpt.excpt("Unknown protocol #{p.ip_p}")
	end
	$stderr.puts " ---- bytes.length=#{bytes.length} %x %x" % [ bytes[(p.ip_hl*4)+8], bytes[(p.ip_hl*4)+9]] if Debug&2==2
	resp = IPv4.creator(bytes[offset,bytes.length-offset])	# make a packet from embeded bounce
	resp.ip_options.map { |opt|
		if opt.is_a?(RecordRoute_option)
			parsedOptions=Array1.new unless parsedOptions
			opt.routers.each_index { |i|
				if resp.ip_options[0].routers[i].to_s != "0.0.0.0"
					parsedOptions << "hop %d %s ," %
						[ i+1,resp.ip_options[0].routers[i].to_s]
				end
			}
			$stderr.puts "--- Got from #{p.ip_src}: RR #{parsedOptions.join(' ')}" if Debug&2==2
		else
			if opt
				parsedOptions=Array1.new unless parsedOptions
				parsedOptions << "unknownOpt=#{opt.to_s}"
			else
				$stderr.puts "Got nil option from #{p.ip_src}-->#{p.ip_dst}"
			end
		end
	}
	return parsedOptions
end
#################################################################
# parse and record info from a response from a modeUse trace packet
def handleUseTraceResponse(ip,r)
	resp=r.response.packet
	raise MyExcpt.excpt("Call to handleUseTraceResponse when #{ip}") unless ip[:state] == ModeUse_RRTrace
	key = "TTL "+ip[:ttl].to_s+" it="+ip[:iteration].to_s # key = "ttl=1 it=2" ; is unique
	nextIteration=false
	rrArray=parseRR(resp)
	str = "#{resp.ip_src} (??) ?? rtt=#{r.rtt} s t=?? %s Macro" % [ rrArray ? "RR, #{rrArray.join(' ')}" : ""]
	ip[:data][key]=str
	ip[:consecutiveBadResponses]=0		# got a response
	ip[:nextPacket]=nil		# by default, we don't create a new packet for the next round
	if resp.ip_p == IPPROTO_ICMP
		if resp.icmp_type==ICMP_UNREACH
			ip[:state]=ModeUse_Unreach	# stop tracing if we got an UNREACH resp; 
			ip[:icmp_type]=resp.icmp_type	# NOTE: due to the stop list, we should rarely get these
			ip[:icmp_code]=resp.icmp_code	# we only stop to avoid poking at end hosts to avoid abuse reports
		else
			if resp.icmp_type!=ICMP_TIMXCEED	# this should be the common response
				ip[:state]=ModeUse_UnknownICMP
				ip[:icmp_type]=resp.icmp_type
				ip[:icmp_code]=resp.icmp_code
			end
		end
		if ip[:stopList].include?(resp.ip_src.to_s) ||	# if hit an ip in the stopList
			# or if we are doing RR and have filled the RR buffer
			((ip[:iteration]%2==1) && (rrArray)&& (rrArray.length>=9))
			nextIteration=true  # goto next stage
		end
	else
		if resp.ip_p == IPPROTO_TCP
			StopDistance.times{ |i|	# try to record new stopLists, b/c clearly the old one didn't work
				prevkey = "TTL "+(ip[:ttl]-i-1).to_s+" it="+ip[:iteration].to_s
				if ip[:data].has_key?(prevkey)
					stoplistip=ip[:data][prevkey].split[0]
					ip[:stopList] << stoplistip
				end
			}
			nextIteration=true
		else
			# not TCP or ICMP: --> really weird
			ip[:state]=ModeUse_UnknownProto
			ip[:proto]=resp.ip_p
		end
	end
	if nextIteration 
		if ip[:iteration] >= MaxIterations
			ip[:state]=ModeUse_Done
		else
			ip[:iteration]+=1
		end
	end
	if ip[:state] == ModeUse_RRTrace
		if  nextIteration
			ip[:ttl]=1
		else
			ip[:ttl]+=1
		end
		ip[:nextPacket] = true
	else
		printUseFinishedIP(ip)
	end
end
#################################################################
def modeUseUpdatePacket(ipQ,ip,response)	# should have readlock before coming here
	$stderr.puts "--- in #{__FILE__}:#{__LINE__}" if $verbose
	if !response
		ip[:state]=ModeUse_NeedInit
	end
	ip[:retrycount]=0
	case ip[:state]
	when ModeUse_NeedInit then	# initialize
		ip[:state]=ModeUse_RRTrace
		ip[:ttl]=1
		ip[:iteration]=1
		ip[:data]=Hash2.new
		ip[:consecutiveBadResponses]=0
		ip[:nextPacket]=true
	when ModeUse_RRTrace then
		# sanity checks
		if ip[:ttl]>64
			$stderr.puts "!!! IP #{ip[:ip]} perversely bad state -- skipping"
			ip[:state]=ModeUse_Corruptstate
			ip[:nextPacket]=nil
			printUseFinishedIP(ip)
		elsif !response.response	# if we timed out and got no response
			ip[:consecutiveBadResponses]+=1
			if ip[:consecutiveBadResponses]>= MaxConsecutiveBadResponses
				ip[:state]=ModeUse_TooManyBadResponses
				ip[:nextPacket]=nil
				printUseFinishedIP(ip)
			else
				ip[:ttl]+=1
				ip[:nextPacket]=true
			end
		else	# got a reponse, this code is lengthy, so move elsewhere
			handleUseTraceResponse(ip,response)
		end
	else 
		raise MyExcpt.excpt("Weird ModeUse State: #{ip[:ip]}==#{ip[:state]}")
	end
	if ip[:nextPacket] # if this field is valid, then queue it to be sent
		ipQ.push(ip) # enqueue to be sent
	end
end

#################################################################
def doModeUse(inputFileName)
	ipQ = Queue.new
	iplist=Array.new
	threadList=Array.new
	$trackIP=LockingHash.new if $trackIPMode
	if ! File.stat(inputFileName)
		usage "File '#{inputFileName}': #{$!}"
	end
	nIPs = `wc -l #{inputFileName}`.split[0].to_i
	$progressbar=ProgressBar.new("IPs finished",nIPs)
	$stderr.puts "File #{inputFileName} has #{nIPs} IPs; randomizing "
	nIPs = `wc -l #{inputFileName}.randomized`.split[0].to_i
	$stderr.puts "Done randomizing: #{nIPs} "
	inputFile= File.new("#{inputFileName}.randomized")
	# setup some shared variables
	workers = Workers.new(NumThreads+1)
	readcond = ConditionVariable.new
	readlock= Mutex.new
	$progressbar.set(0)
	spawnObjectCount if $fakeMode		# for debugging our mem leak
	spawntrackIP if $trackIPMode
	desiredQueueSize=MaxQueueSize
	readlock.synchronize {
		workers.startWorking(Thread.current[:index])
		# spawn off NumThread new threads
		$stderr.puts "Spawning #{NumThreads} threads: MaxQueueSize=#{MaxQueueSize}"
		NumThreads.times { |threadId|
			threadList << Thread.new(threadId) { |id|
				Thread.current[:index]=id
				Kernel.sleep(threadId.to_f) # make each thread sleep a bit to avoid syncronizing and pcap overloaded errors
				packetConsumer(ipQ,workers,readlock,readcond,:modeUseUpdatePacket)
			}
		}
		# now read the rest of the 
		inputFile.each { |line|
			while(ipQ.size>= desiredQueueSize)	# wait for threads to signal the queue is not full
				# $stderr.puts "Producer thread sleeping: #{ipQ.size} ips on queue" 
				readcond.wait(readlock)	
				desiredQueueSize=MinQueueSize	# fill up the queue to MaxQ first, and then only
								# fill it to the min queue size afterwards
			end
			line.chomp!
			ip=TargetIp.new
			l = line.split 
			# "DONE: 165.123.168.1 : 165.123.168.1 128.91.10.6 198.32.42.250"
			if l[0] !~  /DONE:/
				$stderr.puts "skipping #{l[1]} :: #{l[0]}"
				$progressbar.inc
				next
			end
			ip[:ip]=l[1]
			ip[:stopList]=l[3,l.size-1] # put the rest of line into stoplist
			#$stderr.puts "stoplist=#{ip[:stopList].size} l=#{l.size}"
			modeUseUpdatePacket(ipQ,ip,nil)
			$trackIP.add(ip[:ip])	if $trackIPMode
			readcond.broadcast()	# tell ppl there is new stuff in the queue
		}
	}
	workers.stopWorking(Thread.current[:index]) # signal that no more work is coming from this thread
	$stderr.puts "Done spooling new IPs; waiting for threads to finish"
	
	# wait for threads to finish
	threadList.each { |thread|
		thread.join
	}
end

#######################################3
def threadLister
	Thread.new {
		while true
			Kernel.sleep(30)
			$stderr.puts "THREAD Count #{Thread.list.length} "
		end
	}
end
#######################################3
def spawntrackIP(delay=30)
	Thread.new { 
		while true
			$stderr.puts "TRACKIP : #{$trackIP.count} ips in memory"
			Kernel.sleep(delay)
		end

	}
end
#######################################3
def spawnObjectCount(file="ruby-objectcount.out",delay=5)
	Thread.new { 
		while true
			Thread.critical=true
			GC.start
			list=Hash3.new {|h,k| h[k]=0 }
			ObjectSpace.each_object { |o|
				list[o.class.to_s]+=1
			}

			list.keys.sort { |a,b| list[b] <=> list[a] }[0..9].each { |k|
				$stderr.puts "OBJcount: #{k}  = #{list[k]}"
			}
			Thread.critical=false
			Kernel.sleep(delay)
		end

	}
end

#################################################################
# Main Code!

if $0 == __FILE__
	Thread.abort_on_exception = true	# to avoid threads silently dying
	$stderr.sync=true	# this should be redundant, but isn't

	# dear god, why don't I just use getopt()
	if ARGV[0] == '-v'
		$verbose=1
		ARGV.shift
	end

	if ARGV[0] == '-f'
		$fakeMode=true
		require 'scriptroute_stub.rb'
		ARGV.shift
	end

	if ARGV[0] == "-genStopList"
		$mode=ModeGen
	elsif ARGV[0] == "-useStopList"
		$mode=ModeUse
	elsif ARGV[0] == nil
		usage
	else
		usage(ARGV[0],"invalid arg")
	end

	inputFile = ARGV[1]

	usage unless(inputFile)

	$localip= IPSocket.getaddress(Socket.gethostname)

	$stderr.puts "Using Avg=#{AvgBandwidthBPS}B/s Probes/Train=[#{MinPacketsPerTrain},#{MaxPacketsPerTrain}]"

	begin
		$stderr.puts "Scriptroute daemon v#{Scriptroute.DaemonVersion.to_a.join('.')}; " + 
			" Interpreter version v#{Scriptroute::InterpreterVersion.to_a.join('.')}"
		rescue NoMethodError=>e
			$stderr.puts "Need to invoke with srinterpreter, i.e."
			$stderr.puts "	srinterpreter #{$0} #{ARGV.join(' ')}"
			exit!(1)
	end

	Thread.current[:index]=NumThreads
	if ! Kernel::test(?s, "#{inputFile}.randomized")
		`randomize < #{inputFile} #{FilterCmd}  > #{inputFile}.randomized`
		nIPs = `wc -l #{inputFile}.randomized`.split[0].to_i
	else
		$stderr.puts "Already randomized"
	end
	threadLister if $fakeMode
	if($mode==ModeGen)
		doModeGen(inputFile)
	else
		$stderr.puts "Localip==#{$localip}"
		doModeUse(inputFile)
	end
end
