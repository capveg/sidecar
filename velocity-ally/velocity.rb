#!/usr/bin/ruby

require 'thread'
require 'idvelocity.rb'


maxBandwidth=200*1024
reps=200
delay=0.0
probesize=40# 40 == estimated probe size


Randomize='randomize'
ThreadDebug=nil
## silliness that's an artifact of scriptroute's send_train function
probesPerSecond=maxBandwidth/probesize
maxTrainSize=20
$timeoutTime=5.0
$maxThreads=[(probesPerSecond/maxTrainSize) * $timeoutTime, 100].min


$stderr.puts "Parameters: maxBand=#{maxBandwidth} nThreads=#{$maxThreads} "

if Kernel.test(?f,ARGV[0]+".random") and Kernel.test(?<,ARGV[0],ARGV[0]+".random")
  $stderr.puts "Using already randomized file #{ARGV[0]}.random"
else
  $stderr.puts "Randomizing to file #{ARGV[0]}.random"
  Kernel.system("%s < %s > %s.random" % [ Randomize,
		  ARGV[0],
		  ARGV[0]])
end

ips=Array.new
File.open(ARGV[0]+".random").each { |line|
  if line =~ /^(\d+\.\d+\.\d+\.\d+)/
    ips << line.chomp
  else
    $stderr.puts "UNparsed input: #{line}"
  end
}

train= Array.new
$threadLock = Mutex.new
$threadCond = ConditionVariable.new
$activeThreads=0


# magic lines
Thread.abort_on_exception = true        # to avoid threads silently dying
$stderr.sync=true       # this should be redundant, but isn't

def do_sendtrain(train)
  # send the train
  $threadLock.synchronize {
	while $activeThreads >= $maxThreads
		$threadCond.wait($threadLock)	# wait until there is one less thread
	end
	$activeThreads+=1
	$stderr.puts "activeThreads=#{$activeThreads} GRAB" if ThreadDebug
  }
  Thread.new {
	  outputbuffer=[]
  	begin
  	  sleepTime=rand(0)*$timeoutTime
	  $stderr.puts "Sleeping #{sleepTime} s" if ThreadDebug
	  sleep(sleepTime)	# sleep some random interval amount of time to not run over other threads
	  responses = Scriptroute::send_train( train )
	  responses.each { |response|
	    next unless response.probe	# this won't be set if the pcap buf overflowed
	    dst = response.probe.packet.ip_dst
	    if response.response
	      r = response.response.packet
	      icmp_src = r.ip_src
	      icmp_id  = r.ip_id.to_s

	      high = (r.ip_id >> 8 ) & 0xFF
	      low = r.ip_id & 0xFF
	      swapped_id = (low << 8) + high

	      resp_type = r.class.to_s.sub(/^Scriptroute::/,'')
	      resp_type += "_t=#{r.icmp_type}_c=#{r.icmp_code}" if resp_type == "Icmp"
	      arrive = response.response.time.to_f.to_s
	    else
	      icmp_src = '-'
	      icmp_id  = '-'
	      resp_type= '-'
	      arrive   = '-'
	    end
	    #       dst  icmpsrc  arrive id id(hostorder) type
	    outputbuffer << sprintf("%16s %16s %20s %7s %7s %12s\n" % [
		      dst,
		      icmp_src,
		      arrive,
		      icmp_id,
		      swapped_id,
		      resp_type])
	  }
	  ensure
	  $threadLock.synchronize {
		outputbuffer.each { |l|		# flush output while we have the lock
			puts l			# actually print the data
		}
		$activeThreads-=1
		$stderr.puts "activeThreads=#{$activeThreads} RELEASE" if ThreadDebug
		raise "Too many Thread deactivates" unless $activeThreads>=0
		$threadCond.signal 	# tell another thread it's their turn to go
	  }
	  end
   }

end

reps.times {
  ips.each { |ip|
    p = Scriptroute::Tcp.new(0)
    #p = Scriptroute::Udp.new(12)
    p.ip_dst=ip
    train.push(Struct::DelayedPacket.new(delay,p))
    if(train.length >maxTrainSize)
      do_sendtrain(train)
      train = Array.new
    end
  }
  if train.length>0
    do_sendtrain(train)
    train = Array.new
  end
}
