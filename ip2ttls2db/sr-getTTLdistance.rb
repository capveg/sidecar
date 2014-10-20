#!/usr/bin/srinterpreter 

class Array
  def min
    if(self.length == 0) then 
      raise "Array min()'d is empty."
    end
    inject(self[0]) { |n, value| ((n < value) ? n : value) }
  end
  def shuffle!
    index = 0
    tmp = nil
    (size-1).downto(0) {|index|
      other_index = rand(index+1)
      next if index == other_index
      tmp = self[index]
      self[index] = self[other_index]
      self[other_index] = tmp
    }
    self
  end
end
# $useUDP=true
#
#
#if($useUDP) then	# if UDP probes are requested
#	probes.push( Scriptroute::Udp.new(12) )	
#end

#puts "Got ARGV=#{ARGV.join(',')}"
TcpProbe=1
UdpProbe=2
IcmpProbe=4

NotSent=-3
Filtered=-2
Timedout=-1


ARGV.length > 0 or raise "need ips to probe"

def packet2str(p)
      case p
      	when Scriptroute::Tcp
		if p.flag_rst
			":TCP_RST"
		else
			":TCP"
		end
	when Scriptroute::Udp
		":UDP"
	when Scriptroute::Icmp
		case p.icmp_type
		    when Scriptroute::Icmp::ICMP_ECHOREPLY
		    	":ICMP_ECHOREPLY"
		    when Scriptroute::Icmp::ICMP_UNREACH
		    	":ICMP_U_#{p.icmp_code}"
		    else
			":ICMP_UNK_#{p.icmp_type}"
		end
	else
		"Unknown!"
	end
end

interval = [ 20.0 / 3.0 / ARGV.length, 1 ].min
udpen = Array.new
tcpen = Array.new
icmpen = Array.new
responses = Hash.new
rtt = Hash.new
tscrtt = Hash.new
ARGV.each { |key|
	ip,filterStr=key.split(/:/)
	filter=filterStr.to_i
  u, t, i = [Scriptroute::Udp.new(12), 
             Scriptroute::Tcp.new(0), 
             begin	# icmp needs some extra init stuff
               p=Scriptroute::Icmp.new(0)
               p.icmp_type=Scriptroute::Icmp::ICMP_ECHO
               p.icmp_code=0
               p.icmp_seq=1
               p
             end].collect { |probe|
	#$stderr.puts "Trying #{ip}"
    probe.ip_dst=ip
    Struct::DelayedPacket.new(interval,probe)
  } 
  responses[ip]=Hash['Udp' => NotSent, 'Tcp' => NotSent, 'Icmp' => NotSent]	# init responses
  rtt[ip]=Hash['Udp' => -2.0, 'Tcp' => -2.0, 'Icmp' => -2.0]	# init responses
  tscrtt[ip]=Hash['Udp' => -2.0, 'Tcp' => -2.0, 'Icmp' => -2.0]	# init responses

  if filter&UdpProbe !=0
	  responses[ip]['Udp']=Filtered	# filtered
  else 
  	udpen.push(u) 
  end
  if filter&TcpProbe !=0
	  responses[ip]['Tcp']=Filtered	# filtered
  else 
  	tcpen.push(t) 
  end
  if filter&IcmpProbe !=0
	  responses[ip]['Icmp']=Filtered	# filtered
  else 
  	icmpen.push(i) 
  end
}
train = [ udpen, tcpen, icmpen ].shuffle!.flatten  
if train.length == 0 
	$stderr.puts "All packets filtered!? " + ARGV.join(' ')
	exit 1
end
packets = Scriptroute::send_train( train ) 

packets.each { |tuple|
  begin
    next unless tuple.probe	# this won't be set if the pcap buf overflowed
    destination = tuple.probe.packet.ip_dst
    probe_type = tuple.probe.packet.class.to_s.sub(/^Scriptroute::/,'')
    if(tuple.response) then
      responses[destination][probe_type] = tuple.response.packet.ip_ttl.to_s
      rtt[destination][probe_type] = tuple.rtt
      tscrtt[destination][probe_type] = begin	# the Nspring Offical Method
      					((Scriptroute::CPUFrequencyHz!=nil) && (Scriptroute::CPUFrequencyHz > 0)) ? ( (1.0 *
					    (tuple.response.tsc - tuple.probe.tsc)) /
					    Scriptroute::CPUFrequencyHz ) : -1.0
					      rescue => e
						      $stderr.puts e
						      -1.0
				      end

      case tuple.probe.packet
      	when Scriptroute::Tcp
		if ! tuple.response.packet.instance_of?(Scriptroute::Tcp) || !tuple.response.packet.flag_rst
			responses[destination][probe_type] +=packet2str(tuple.response.packet)
			#$stderr.puts "Got non-rst tcp response for #{tuple.probe.packet.to_s} : #{tuple.response.packet.to_s}"
		end
	when Scriptroute::Udp
		if ! tuple.response.packet.instance_of?(Scriptroute::Icmp)|| 
				tuple.response.packet.icmp_type != Scriptroute::Icmp::ICMP_UNREACH ||
				tuple.response.packet.icmp_code !=Scriptroute::Icmp::ICMP_UNREACH_PORT
			responses[destination][probe_type] +=packet2str(tuple.response.packet)
			#$stderr.puts "Got non-unreach icmp response for #{tuple.probe.packet.to_s} : #{tuple.response.packet.to_s}"
		end
	when Scriptroute::Icmp
		if ! tuple.response.packet.instance_of?(Scriptroute::Icmp) ||
			tuple.response.packet.icmp_type != Scriptroute::Icmp::ICMP_ECHOREPLY ||
			tuple.response.packet.icmp_code != 0
			responses[destination][probe_type] +=packet2str(tuple.response.packet)
			#$stderr.puts "Got non-echo reply icmp response for #{tuple.probe.packet.to_s} : #{tuple.response.packet.to_s}"
		end
	else
		$stderr.puts "Weird unknown probe type: #{tuple.probe.packet.class.to_s} :: #{tuple.probe.packet.to_s}"
	end
    else 
      responses[destination][probe_type] = Timedout	# no response
    end
  rescue => e
    $stderr.puts "barf: #{e}" 
  end
}

responses.each { |ip,results|
  print '%-20s' % [ip]
  [ 'Udp', 'Tcp', 'Icmp' ].each { |probe_type|
    print '%10s %3s %7.6f %7.6f' % [ probe_type, results[probe_type], rtt[ip][probe_type], tscrtt[ip][probe_type]]
  }
  puts ''
}
  
