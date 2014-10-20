#! ../srinterpreter 

# a small library of routines for constructing packets
# as strings to hand off to the interpreter.

IPPROTO_ICMP = 1
IPPROTO_TCP = 6
IPPROTO_UDP = 17

ICMP_ECHO = 8
ICMP_ECHOREPLY = 0 
ICMP_UNREACH = 3 
ICMP_TIMXCEED = 11
ICMP_TIMESTAMP = 13 
ICMP_TIMESTAMPREPLY = 14 
ICMP_PARAMETERPROB = 12

IPOPT_TS = 68
IPOPT_TIMESTAMP = IPOPT_TS
IPOPT_RR = 7

IPOPT_TS_TSONLY = 0
IPOPT_TS_TSANDADDR = 1
IPOPT_TS_PRESPEC = 3

class Array
  def inject(n)
    each { |value| n = yield(n, value) }
    n
  end
  def sum
    inject(0) { |n, value| n + value }
  end
  def max
    inject(0) { |n, value| ((n > value) ? n : value) }
  end
  def even_subscripts
    r = Array.new
    0.step(self.length, 2) { |i| r.push(self[i]) }
    r
  end
  def odd_subscripts
    r = Array.new
    1.step(self.length, 2) { |i| r.push(self[i]) }
    r
  end
end

class IPaddress
  def initialize(n)
    if(n.is_a?(String)) then
      shf = 32
      @addr = n.split('.').map { |i| shf -= 8; i.to_i << shf }.sum
    elsif(n.is_a?(IPaddress)) then
      @addr = n.to_i
    else
      @addr = n
    end
  end
  def to_s
    [ @addr >> 24, @addr >> 16, @addr >> 8, @addr ].map { |i| i & 0xff }.join(".")
  end
  def to_i
    @addr
  end
end

class IPv4
  attr_reader :ip_hl, :ip_v, :ip_tos, :ip_len, :ip_id, :ip_off, 
    :ip_ttl, :ip_p, :ip_sum, :ip_src, :ip_dst, :ip_options
  attr_writer :ip_tos, :ip_id, :ip_off, 
    :ip_ttl, :ip_sum,  :ip_dst, 
    :ip_options, :ip_src		# unsafe version! NOT FOR GENERAL SCRIPTROUTE USE


  def ip_dst=(x)
    @ip_dst = IPaddress.new(x)
  end

  def marshal
    calculate_packet_len
    [ (@ip_v << 4) + @ip_hl, @ip_tos, @ip_len, 
      @ip_id, @ip_off, 
      @ip_ttl, @ip_p, @ip_sum,
      @ip_src.to_i, 
      @ip_dst.to_i ].pack("ccn" + "nn" + "ccn" + "N" + "N") + 
      @ip_options.map { |o| o.marshal }.join
  end
  def ip_payload_len
    raise "ip_payload_len is a pure virtual function in IPv4"
  end
  def calculate_header_len 
    @ip_hl = [ 5 + ((ip_options.map { |o| o.ipt_len }.sum)/4.0).ceil, 15 ].min # at most 15
  end
  def calculate_packet_len 
    calculate_header_len # ensures @ip_hl is set properly
    @ip_len = ip_payload_len + (@ip_hl * 4)
  end
  def add_option(opt)
    @ip_options.push(opt)
    calculate_header_len
  end
  def initialize(p) 
    if(p.is_a?(Fixnum)) then
      @ip_v = 4
      @ip_tos = 0
      @ip_id = 11 
      @ip_off = 0
      @ip_ttl = 64
      @ip_p = p
      @ip_sum = 0
      @ip_src = 0
      @ip_dst = 0
      @ip_options = Array.new
      calculate_packet_len
    else
      raise "need a protocol number to instantiate an ipv4 packet"
    end
  end
  
  @@creators = Hash.new
  def IPv4.creator(str) 
    ip_vhl, ip_tos, ip_len,
      ip_id, ip_off,
      ip_ttl, ip_p, ip_sum,
      ip_src, ip_dst = str.unpack("ccn" + "nn" + "ccn" + "N" + "N");
    ip_hl = ip_vhl & 0xf;
    if(@@creators[ip_p]) then
      pkt = (@@creators[ip_p]).call(str[(ip_hl * 4) .. ip_len])

      pkt.ipv4_unmarshal(str)
      pkt
    else
      raise "unknown protocol #%d in %s" % [ ip_p, str.unpack("C*").map { |c| "%x" % c }.join(' ') ]
    end
  end

  def ipv4_unmarshal(str)
    ip_vhl, @ip_tos, @ip_len,
      @ip_id, @ip_off,
      @ip_ttl, @ip_p, @ip_sum,
      ip_src, ip_dst = str.unpack("ccn" + "nn" + "ccn" + "N" + "N");
    @ip_src, @ip_dst = [ip_src, ip_dst].map { |addr| IPaddress.new(addr) }
    @ip_hl = ip_vhl & 0xf;
    @ip_v = (ip_vhl & 0xf0) >> 4;
    @ip_options = Array.new
    if(@ip_hl > 5) then
      add_option(IPoption_base.creator(str[20 .. (@ip_hl*4)]))
    end
  end

  def to_s
    "%s > %s ttl%d" % [ @ip_src, @ip_dst, @ip_ttl ] + 
      @ip_options.map { |o| o.to_s }.join(", ")
  end
  private :initialize
  private :marshal
end

class IPoption_base
  attr_reader :ipt_code, :ipt_len, :ipt_ptr
  attr_writer :ipt_ptr
  @@creators = Hash.new
  def IPoption_base.creator(str) 
    ipt_code, ipt_len, ipt_ptr = str.unpack("ccc")
    if(@@creators[ipt_code]) then
      pkt = (@@creators[ipt_code]).call(str)
    else
      raise "unknown ip option code %d" % ipt_code
    end
  end
  def initialize(*rest) 
    if(rest.length == 3) then
      @ipt_code = rest[0]
      @ipt_len = rest[1]
      @ipt_ptr = rest[2]
    else
      @ipt_code, @ipt_len, @ipt_ptr = rest[0].unpack("ccc")
    end
  end
  def marshal
    # doesn't end on a word. 
    [ @ipt_code, @ipt_len, @ipt_ptr ].pack("ccc")
  end
  def to_s
    ": opt: code %d len %d ptr %d" % [ @ipt_code, @ipt_len, @ipt_ptr ]
  end
  # must be instatiated through a derived class.
  private :marshal
end

class Timestamp_option < IPoption_base
  attr_reader :ts_flag, :ts_overflow
  attr_reader :routers, :times
  @@creators[IPOPT_TS] = lambda { |hdr|
    p = Timestamp_option.new(hdr)
  }
  def initialize(flag_or_str)
    if(flag_or_str.is_a?(Fixnum)) then
      @routers = Array.new
      @times = Array.new
      @ts_flag = flag_or_str
      super(IPOPT_TS, 36, 5) # maximum length is 40, but tcpdump whines.
    else
      ipt_code, ipt_len, ipt_ptr, ipt_of_fl = flag_or_str.unpack("cccc");
      @ts_flag = ipt_of_fl & 0x0f
      @ts_overflow = (ipt_of_fl & 0xf0) >> 4
      @routers, @times = 
        case @ts_flag 
        when IPOPT_TS_TSONLY
          [ nil, flag_or_str.unpack("xxxxN*") ]
        when IPOPT_TS_TSANDADDR,  IPOPT_TS_PRESPEC
          all = flag_or_str.unpack("xxxxN*")
          [ all.even_subscripts.map { |rtr| IPaddress.new(rtr) }[0...(ipt_len/8)], all.odd_subscripts[0...(ipt_len/8)] ] 
        else
          raise "bad timestamp flag: #{@ts_flag} (code: #{ipt_code}, len: #{ipt_len}, ptr: #{ipt_ptr})"
        end
      super( flag_or_str )
    end
  end
  def marshal
    super + [ @ts_flag ].pack("c") + # oflw will be init'd to zero
      Array.new(@ipt_len - 4, 0).pack("c*")
  end
end

class RecordRoute_option < IPoption_base
  attr_reader :routers
  @@creators[IPOPT_RR] = lambda { |hdr|
    p = RecordRoute_option.new(hdr)
  }
  def initialize(*rest)
    if(rest.length == 0) 
      super(IPOPT_RR, 39, 4) 
      @routers = Array.new((@ipt_len - 3 + 1)/4, 0)
    else
      super(rest[0]) 
      @routers = rest[0][3..@ipt_len].unpack("N*").map { |addr| IPaddress.new(addr) }
    end
  end
  def marshal
    super + @routers.pack("N*")  + "\0"
  end
  def to_s
    super + ': RR: {' + @routers.join(", ") + '}'
  end
end

class UDP < IPv4
  attr_reader :uh_sport, :uh_dport, :uh_ulen, :uh_sum
  attr_writer :uh_dport, :uh_sum

  @@creators[IPPROTO_UDP] = lambda { |hdr|
    uh_sport, uh_dport, uh_ulen, uh_sum = hdr.unpack("nnnn")
    if uh_sport==123 || uh_dport==123  then
    	p = NTP.new(hdr[8..hdr.length])
    	p.udp_unmarshal(hdr)
    else 
    	p = UDP.new(hdr)
    end
    p
  }
    
  def ip_payload_len 
    @uh_ulen
  end

  def initialize(paylen_or_str = 0)
    if(paylen_or_str.is_a?(Fixnum)) then
      if( paylen_or_str < 0) then raise "payload length must be >= 0" end
      @uh_ulen = paylen_or_str + 8
      if(@uh_ulen > 1480) then
        raise "desired packet too big"
      end
      @uh_sport = 32945
      @uh_dport = 33434
      @uh_sum = 0
      super( IPPROTO_UDP )
    else
      @uh_sport, @uh_dport, @uh_ulen, @uh_sum = paylen_or_str.unpack("nnnn")
    end
  end

  def marshal
#    payload = "a%d"% (@payload_len)
#    puts payload
    if(@uh_ulen < 8) then warn "uh_ulen should be at least 8" end
    super + [ @uh_sport, @uh_dport, @uh_ulen, @uh_sum ].pack("nnnn")  + 
           if ( self.class == UDP ) then
             "\0" * ( @uh_ulen - 8 )
           else
             "" # the subclass will take care of it
           end
             
  end

  def udp_unmarshal(str)
	@uh_sport, @uh_dport, @uh_ulen, @uh_sum = str.unpack("nnnn")
  end

  def to_s
    super + " UDP %d > %d len %d" % [ @uh_sport, @uh_dport, @uh_ulen ] 
  end

end

class TCP < IPv4
  # flags don't work
  attr_reader :th_sport, :th_dport, :th_sum, :th_seq, :th_ack,
    :th_win, :th_flags, :flag_fin, :flag_syn, :flag_rst, :flag_push,
    :flag_ack, :flag_urg, :th_win, :th_sum, :th_urp
  attr_writer :th_sport, :th_dport, :th_sum, :th_seq, :th_ack,
    :th_win, :th_flags, :flag_fin, :flag_syn, :flag_rst, :flag_push,
    :flag_ack, :flag_urg, :th_win, :th_sum 
  attr_reader :ip_p, :ip_payload_len

  @@creators[IPPROTO_TCP] = lambda { |hdr|
    TCP.new(hdr)
  }
  
  def initialize(paylen_or_str = 0)
    if(paylen_or_str.is_a?(Fixnum)) then
      @ip_payload_len = paylen_or_str + 20 # tcp header 
      @ip_p = IPPROTO_TCP
      @th_dport = 80
      @th_sport=0
      @th_urp=0
      @th_sum=0
      super(IPPROTO_TCP)
    else
      @th_sport, @th_dport, @th_seq, @th_ack, reserved, @th_flags, @th_win, @th_sum, @th_urp = paylen_or_str.unpack("nnNNccnnn")
    end
  end
  def marshal
    super + [ @th_sport, @th_dport, @th_seq, @th_ack, 0x50, @th_flags, @th_win, @th_sum,
      @th_urp ].pack("nnNNccnnn")
    # TODO plus payload length
  end
end

class ICMP < IPv4
  attr_reader :icmp_type, :icmp_code, :icmp_cksum
  attr_reader :ip_p, :ip_payload_len

  @@icmp_creators = Hash.new
  @@creators[IPPROTO_ICMP] = lambda { |hdr|
    icmp_type, icmp_code, icmp_cksum = hdr.unpack("ccn")
    if(@@icmp_creators[icmp_type]) then
      pkt = @@icmp_creators[icmp_type].call(hdr)
    else
      raise "unknown icmp type #%d" % icmp_type
    end
  }

  def initialize(type_or_str)
    if(type_or_str.is_a?(Fixnum)) then
      @ip_p = IPPROTO_ICMP
      @icmp_type = type_or_str
      @icmp_code = 0
      @ip_payload_len=0
      super(IPPROTO_ICMP) 
    else
      @icmp_type, @icmp_code, @icmp_cksum = type_or_str.unpack("ccn")
    end
  end

  def marshal
    @icmp_type or raise "type is nil"
    @icmp_code or raise "code is nil"
    @icmp_cksum = 0
    super + [ @icmp_type, @icmp_code, @icmp_cksum ].pack("ccn")
  end
  def to_s
    super + ": ICMP: type %d code %d cksum %d" %[ @icmp_type, @icmp_code, @icmp_cksum ]
  end
  #instantiate echo or tstamp instead.
  private :marshal 
end

class ICMPecho < ICMP
  attr_reader :icmp_id, :icmp_seq
  attr_writer :icmp_seq
  @@icmp_creators[ICMP_ECHO] = 
    @@icmp_creators[ICMP_ECHOREPLY] = lambda { |hdr|
    ICMPecho.new(hdr)
  }
  def initialize(paylen_or_str = 0)
    if(paylen_or_str.is_a?(Fixnum)) then
      if( paylen_or_str < 0) then raise "payload length must be >= 0" end
      @ip_payload_len = paylen_or_str + 4 + 4
      @icmp_id = 666
      @icmp_seq = 1
      super(ICMP_ECHO)
    else
      # x is skip forward a character.
      @ip_payload_len = paylen_or_str.length - 8
      @icmp_id, @icmp_seq = paylen_or_str.unpack("xxxxnn")
      super(paylen_or_str)
    end
  end
  def marshal
    super + [ @icmp_id, @icmp_seq ].pack("nn") + "\0" * ( @ip_payload_len - 4 - 4 )
  end
  def to_s
    super + ": ECHO: id %d seq %d len %d" % [ @icmp_id, @icmp_seq, @ip_payload_len ] 
  end
end

class ICMPtstamp < ICMP
  attr_reader :icmp_id, :icmp_seq
  attr_reader :icmp_otime, :icmp_rtime, :icmp_ttime
  attr_writer :icmp_seq
  def initialize(payload_len = 0)
      if( payload_len < 0) then raise "payload length must be >= 0" end
    @ip_payload_len = payload_len + 4 + 16
    @icmp_id = 666
    @icmp_seq = 1
    super(ICMP_TIMESTAMP)
  end
  def marshal
    super + [ @icmp_id, @icmp_seq, @icmp_otime, @icmp_rtime, @icmp_ttime ].pack("nnNNN")
  end
end

# also handles time exceeded messages for now
# (same format, different code )
class ICMPunreach< ICMP
  attr_reader :contents
  @@icmp_creators[ICMP_UNREACH] = @@icmp_creators[ICMP_TIMXCEED] = 
                                  lambda { |hdr|
    ICMPunreach.new(hdr)
  }
  def initialize(string) # can't create a new one.
    # first four are code, type, checksum.
    # second four are undefined
    @contents = IPv4.creator(string[8..-1])
    super(string)
  end
  def marshal
    raise "not supported"
  end
  def to_s
    super + " ( " + @contents.to_s + " )"
  end
end

class NTP < UDP
  attr_accessor :leap_indicator, :version_number, :mode, :stratum
  attr_accessor :poll_interval, :precision, :root_delay
  attr_accessor :root_dispersion, :reference_identifier
  attr_accessor :reference_timestamp, :originate_timestamp
  attr_accessor :receive_timestamp, :transmit_timestamp

  def initialize(paylen_or_str = 0)
    if(paylen_or_str.is_a?(Fixnum)) then
      if( paylen_or_str < 0) then raise "payload length must be >= 0" end
	
      @leap_indicator = 3 # alarm condition / clock not synchronized
      @version_number = 4 # unclear if it should be.
      @mode = 3 # client
      @stratum = 0 # unspecified
      @poll_interval = 4 # 16s
      @precision = -6 # emulate ntpdate, though -20 is more likely
      @root_delay = 1.0 # packed funny.
      @root_dispersion = 1.0 # packed funny.
      @reference_identifier = '0.0.0.0'
      @reference_timestamp = 0.0
      @originate_timestamp = 0.0
      @receive_timestamp = 0.0
      @transmit_timestamp = 0.0
      
      super( paylen_or_str + 48 )
      
      @uh_dport = 123
      
    else
      ntp_unmarshal(paylen_or_str)
    end
  end

  def ntp_unmarshal(str)

    ntp_lvm, @stratum, @poll_interval, @precision,
    root_delay1,root_delay2,
    root_dispersion1,root_dispersion2,
    r1,r2,r3,r4,
    reference_timestamp1,reference_timestamp2,
    originate_timestamp1,originate_timestamp2,
    receive_timestamp1,receive_timestamp2,
    transmit_timestamp1, transmit_timestamp2 = str.unpack( "cccc" +
                                      "nn" +
                                      "nn" +
                                      "cccc" +
                                      "NN" +
                                      "NN" +
                                      "NN" +
                                      "NN");

    @leap_indicator = (ntp_lvm >> 6) & 0xfc
    @version_number = (ntp_lvm & 0x38) >> 3
    @mode = ntp_lvm & 0x07
    @root_delay = root_delay1+root_delay2/65536.0
    @root_dispersion = root_dispersion1+root_dispersion2/65536.0
    @reference_identifier = "%d.%d.%d.%d"% [r1,r2,r3,r4].map{ |i| (i<0)?i+256:i }
    @reference_timestamp = reference_timestamp1 + 0.0 + reference_timestamp2/4294967296.0
    @originate_timestamp = originate_timestamp1 + originate_timestamp2/4294967296.0
    @receive_timestamp = receive_timestamp1 + receive_timestamp2/4294967296.0
    @transmit_timestamp = transmit_timestamp1 + transmit_timestamp2/4294967296.0
    
  end
  
  def float_to_two_shorts(flt)
    flt == nil and raise "need a float"
    [ flt.to_i, ((flt - flt.to_i) * 65536).to_i ]
  end

  def float_to_two_longs(flt)
    flt == nil and raise "need a float"
    [ flt.to_i, ((flt - flt.to_i) * 4294967296).to_i ]
  end

  def to_bits(int, bits)
    ret = ""
    (1..bits).each { |b|
      ret += (int % 2).to_s
      int /= 2
    }
    ret
  end
  
  
  def marshal
    if ($VERBOSE) then
      puts "marshaling with IP payload length %d" % ip_payload_len 
    end
    super + [ @leap_indicator * 64 + @version_number * 8 + @mode, @stratum, @poll_interval, @precision, 
      float_to_two_shorts(@root_delay),
      float_to_two_shorts(@root_dispersion),
      @reference_identifier.to_i, 
      float_to_two_longs(@reference_timestamp),
      float_to_two_longs(@originate_timestamp),
      float_to_two_longs(@receive_timestamp),
      float_to_two_longs(@transmit_timestamp) ].flatten.pack("cccc" +
                                                             "nn" +
                                                             "nn" +
                                                             "N" +
                                                             "NN" +
                                                             "NN" +
                                                             "NN" +
                                                             "NN") + "\0" * ( @uh_ulen - 8 - 48 )
                                                                       
  end
end

# somewhat more friendly to interpret the type of the message first.
class ICMPparamter_problem < ICMP
  attr_reader :icmp_id, :icmp_seq
  attr_writer :icmp_seq
  @@icmp_creators[ICMP_PARAMETERPROB] = lambda { |hdr|
    raise "ICMP_PARAMETERPROB unsupported."
  }
end

def self_test
  m = ICMPecho.new.marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
  # puts "decode: " + Scriptroute::stringpacket(m)
  puts "encode: " + Scriptroute::pkt_from_string(m).to_s
  
  m = ICMPtstamp.new.marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
#  puts "decode: " + Scriptroute::stringpacket(m)
  puts "encode: " + Scriptroute::pkt_from_string(m).to_s
  
  m = TCP.new.marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
#  puts "decode: " + Scriptroute::stringpacket(m)
  puts "encode: " + Scriptroute::pkt_from_string(m).to_s
  
  m = UDP.new.marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
#  puts "decode: " + Scriptroute::stringpacket(m)
  puts "encode: " + Scriptroute::pkt_from_string(m).to_s

  m = UDP.new(8).marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
  puts "decode: " + IPv4.creator(m).to_s
  puts "encode: " + Scriptroute::pkt_from_string(m).to_s

  t = TCP.new
  opt = Timestamp_option.new(1)
  optr = RecordRoute_option.new
  t.add_option(optr)
  t.ip_dst = 0x805f0218
  t.ip_ttl = 3
  t.th_seq = 0x01020304
  t.th_ack = 0x09080706
  m=t.marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
  # puts "decode: " + Scriptroute::stringpacket(m)
  puts "encode: " + Scriptroute::pkt_from_string(m).to_s
  
  #1.times { |i|
  #  m=t.marshal
  #  p = Scriptroute::send_train([ Struct::DelayedPacket.new(0, Scriptroute::pkt_from_string(m) ) ])
  #  puts p[0].probe
  #  puts p[0].response
  #  if(p[0].response && p[0].response.packet.icmp_type != ICMP_PARAMETERPROB) then
  #    puts "****************** (%d)" % p[0].response.packet.icmp_type
  #  end
  #  sleep(1)
  #}
  
  puts "--"

  i = ICMPecho.new(0)
  i.ip_dst = 0x805f0218 # poplar
  # i.ip_dst = 0x84ef3314 # www.cs.ucsd.edu often unresponsive
  i.ip_dst = 0xc6ca4b65 # www.sdsc.edu
  # i.ip_ttl=8
  # rr = RecordRoute_option.new
  rr = Timestamp_option.new(1)
  i.add_option(rr)
  # i.uh_dport = 3000
  m = i.marshal
  puts m.length.to_s + " " + m.gsub(/./) { |b| "%x " % b[0] }
  
  p = Scriptroute::send_train([ Struct::DelayedPacket.new(0,
                                                          Scriptroute::pkt_from_string(i.marshal) ) ])
  puts p[0].probe
  puts p[0].response
  
  if(p[0].response && p[0].response.packet.icmp_type != ICMP_PARAMETERPROB) then
    puts "****************** (%d)" % p[0].response.packet.icmp_type
  end
  
end # self_test

# self_test

# helper function(s) to enhance the scriptroute environment.
module Scriptroute
  class ProbeResponse
    def to_s
      "%s @%5.6f -> %s +%5.6f" % [@probe, @probe.time, (@response or "<none>"), (rtt or "-1")]
    end
  end
end

