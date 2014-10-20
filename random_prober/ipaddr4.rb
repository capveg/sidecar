require 'ipaddr'
require 'my-ipaddr'

class IPAddr4 < IPAddr
  # subclass that trusts its initializer and assumes IPv4
  def in_addr(addr)
    if addr =~ /^(\d+)\.(\d+)\.(\d+)\.(\d+)$/
      (($1.to_i << 24) + ($2.to_i << 16) + ($3.to_i << 8) + ($4.to_i))
    else
      nil
    end
  end
  def initialize(addr)
    @family = Socket::AF_INET
    if( addr.kind_of?(String) ) then
      prefix, len = addr.split('/')
      @addr = in_addr(prefix)
      if(len) then
        mask_len!(len.to_i)
      else
        @mask_addr = IN4MASK 
      end
    else
      @addr = addr
      @mask_addr = IN4MASK 
    end
  end
  # faster include method that only works for ipv4.
  def include?(other)
    if other.kind_of?(IPAddr)
      other_addr = other.to_i
    else # Not IPAddr - assume integer in same family as us
      other_addr   = other.to_i
    end
    return ((@addr & @mask_addr) == (other_addr & @mask_addr))
  end
  def eql?(other)
    if other.kind_of?(IPAddr4) && @family != other.family
      return false
    end
    return (@addr == other.to_i)
  end
  def hash
    @addr.to_i
  end
  def to_s
    # about twice as fast as the map/join based to_s.
    # appears slightly faster than mask then shift.
    "%d.%d.%d.%d" % [ (@addr >> 24) & 0xff, (@addr >> 16) & 0xff, (@addr >> 8) & 0xff, (0xff&@addr) ]   
  end
  def ==(other)
    if other.kind_of?(IPAddr4)
      @addr == other.addr
    else
      @addr == other.to_i # dunno why.
    end
  end
end
