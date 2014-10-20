require 'ipaddr4'

# Lambda hash is a Hash type that takes a closure
# instead of a default value - it automatically creates
# values that don't exist.  Use such a feature at your
# own peril, I use it to avoid if(defined) push else new
# littering my code.
#  The fetch() method of Hash can be used to emulate such
#  a feature (hand it a closure if the key isn't found), but
#  it's not quite enough.
class LambdaHash < Hash
  def initialize (b)
    @creator = b
  end
  def [] (key)
    val = super(key)
    if(val==nil) then
      val = @creator.call(key)
      self[key]=val
    end
    val
  end
end


class IPAddr
  def hash
    @addr
  end
  def host!
    @mask_addr = IN4MASK
    self
  end
  def eql?(other)
    (self == other)
  end
  @@mask_for_len = LambdaHash.new( lambda { |prefixlen|
      masklen = 32 - prefixlen
      ((IN4MASK >> masklen) << masklen)
    })
  def mask_len!(prefixlen)
    @mask_len = prefixlen
    @mask_addr = @@mask_for_len[prefixlen]
	@addr &= @mask_addr
    self
    # orig_mask!(mask)
  end
  attr_accessor :addr
  def +(other)
    # .mask_len!(@mask_len) preserves the length of this prefix.
    # IPAddr.new(@addr + other, @family).mask_len!(@mask_len)
    s = self.clone
    s.addr += other
    s
  end
  def each_component(prefixlen=32)
    if(prefixlen <=0 || prefixlen > 32) then
      raise ArgumentError, "bad prefix length %d" % prefixlen
    end
    masklen = 32 - prefixlen
    mask_addr = ((IN4MASK >> masklen) << masklen)
    increment = 1 << masklen
    next_prefix = self.clone.mask_len!(prefixlen)
    while(self.include?(next_prefix)) do
      yield next_prefix
      next_prefix.addr += increment
    end
  end
  # alias eql? ==
  # at least twice as fast as the map/join based to_s.
  # another ipv4 specific.
  def _to_string(addr)
    "%d.%d.%d.%d" % [ (addr >> 24) & 0xff, (addr >> 16) & 0xff, (addr >> 8) & 0xff, (0xff&addr) ]   
  end
  def to_s
    r = _to_string(@addr) 
  end
  def initialize(addr = '::', family = Socket::AF_UNSPEC)
    if !addr.kind_of?(String)
      if family != Socket::AF_INET6 && family != Socket::AF_INET
	raise ArgumentError, "unsupported address family"
      end
      set(addr, family)
      @mask_addr = (family == Socket::AF_INET) ? IN4MASK : IN6MASK
      return
    end
    prefix, prefixlen = addr.split('/')
    if prefix =~ /^\[(.*)\]$/i
      prefix = $1
      family = Socket::AF_INET6
    end
    # It seems AI_NUMERICHOST doesn't do the job.
    #Socket.getaddrinfo(left, nil, Socket::AF_INET6, Socket::SOCK_STREAM, nil,
    #		       Socket::AI_NUMERICHOST)
  # dammit, wtf is this name lookup bs.  begin
  # dammit, wtf is this name lookup bs.    IPSocket.getaddress(prefix)		# test if address is vaild
  # dammit, wtf is this name lookup bs.  rescue
  # dammit, wtf is this name lookup bs.    raise ArgumentError, "invalid address"
  # dammit, wtf is this name lookup bs.  end
    @addr = @family = nil
    if family == Socket::AF_UNSPEC || family == Socket::AF_INET
      @addr = in_addr(prefix)
      if @addr
	@family = Socket::AF_INET
      end
    end
    if !@addr && (family == Socket::AF_UNSPEC || family == Socket::AF_INET6)
      @addr = in6_addr(prefix)
      @family = Socket::AF_INET6
    end
    if family != Socket::AF_UNSPEC && @family != family
      raise ArgumentError, "address family unmatch"
    end
    if prefixlen
      mask!(prefixlen)
    else
      @mask_addr = (family == Socket::AF_INET) ? IN4MASK : IN6MASK
    end
  end
  # try to get some performance
  def in_addr(addr)
    if addr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
      (($1.to_i << 24) + ($2.to_i << 16) + ($3.to_i << 8) + ($4.to_i))
    else
      nil
    end
  end
end

if $0 == __FILE__ then
  a = IPAddr.new("128.95.219.1")
  b = IPAddr.new("128.95.219.1")

  puts "uniq: %s"  %  [a,b].uniq.join(" ")
  a == b and puts "=="
  a.eql?( b ) and puts "eql?"
  foo = { a => "[]" }
  puts foo[b]

  puts IPAddr.new("128.95.219.1").eql?(IPAddr.new("128.95.219.1"))

  a = IPAddr.new("128.95.219.1")
  b = IPAddr.new("128.95.219.1")

  a == b and puts "=="
  a.eql?( b ) and puts "eql?"
  foo = { a => "[]" }
  puts foo[b]

  IPAddr.new("128.95.219.0/24").each_component(26) { |p|
    puts p | 1
  }
  puts "----"
  IPAddr.new("128.208.4.0/24").each_component(16) { |p|
    puts p | 1
  }
end




