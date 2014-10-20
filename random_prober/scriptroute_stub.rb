# stub to help debug srinterpreted programs


module Scriptroute
	InterpreterVersion = "88.88.88"
	SleepTime = 0.1
	LossRate = 0.01
	MaxTTL = 10
	Icmp = 1
	def Scriptroute.ip2resip(ip,ttl)
		IPaddress.new(~(ip.to_i+ttl))	# cheap way to map a destination to a fake router 
	end
	def Scriptroute.DaemonVersion
		"99.99.99"
	end
	def Scriptroute.send_train(packetTrain)
		Kernel.sleep(SleepTime)		# pretend to go out to the network
		packetTrain.collect { |p|
			raise "passed nil for packet" unless p
			if Kernel.rand < LossRate	# fake packet loss
				resp=nil	
			else
				if p.ip_ttl >= MaxTTL	# fake response from destination
					resp = TCP.new(0)
					resp.ip_dst=p.ip_src
					resp.ip_src=p.ip_dst
					resp.ip_ttl=240
					resp.th_dport=p.th_sport
					resp.th_sport=p.th_dport
					resp.th_seq = rand(4294967295)
					resp.th_ack = rand(4294967295)
					resp.th_flags = 0x14       # should be ACK+RST flag
					resp.th_win = 5840         # Linux default for MSS=1460
				else	# fake response from intermediate router
					#resp = ICMPunreach.new(ICMP_TIMXCEED)
					resp = ICMP.new(ICMP_TIMXCEED)
					resp.ip_src = ip2resip(p.ip_dst,p.ip_ttl)
					resp.ip_dst = p.ip_src
					resp.ip_ttl=240
				end
			end
			PacketResponse.new(p,(resp==nil ? nil : TimedPacket.new(resp)))
		}
	end
end

class TimedPacket
	attr_writer :packet, :time
	def initialize(p)
		@packet=p
		@time=Time.now
	end
	def packet
		@packet
	end
end

class PacketResponse
	attr_writer :probe, :rtt, :response
	def initialize(probe,response)
		@probe=probe
		@response=response
		if response
			@rtt = 0.010	# always 10ms
		else
			@rtt = nil 
		end
	end
	def response
		@response
	end
	def packet
		@probe
	end
	def rtt
		@rtt
	end

	def to_s
		"DON'T PRINT ME I AM A STUB"
	end
end


if $0 == __FILE__
	p "ScriptrouteStub v" + Scriptroute.DaemonVersion
end
