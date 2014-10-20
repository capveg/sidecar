#!/usr/bin/srinterpreter 

class Scriptroute::Icmp_NetmaskReq < Scriptroute::Icmp
	def initialize(size=4)
		raise "Illegal size" unless size>=4
		super()
		self.icmp_type=17
		self.icmp_code=0
		self.icmp_seq=1
		self.ip_ttl=1
	end
	def icmp_addrmask


	end

end

class Scriptroute::Icmp_NetmaskResp < Scriptroute::Icmp_NetmaskReq
end


def getSubnetmask(ip)
	packets = Scriptroute::send_train( [ Scriptroute::Icmp_NetmaskReq.new(4)].collect { |probe|
					probe.ip_dst=ip
					Struct::DelayedPacket.new(0,probe)
				}
			)
	response = packets[0].response ? packets[0].response.packet : nil
	if response
		puts "Got response for #{ip}"
	end
end

ARGV.each { |ip|
	getSubnetmask(ip)
}
