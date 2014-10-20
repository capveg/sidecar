
# refactored for use in the non-xml interfaces parser.

class InterfaceAddress
  attr_accessor :name
  attr_accessor :ipv4prefix
  attr_reader :ipv4addr
  def ipv4addr=(i)
    raise "warning: set ipv4 address twice! (was %s, setting to %s)" % [ @ipv4addr, i ] unless ipv4addr == nil
    @ipv4addr = i
  end
  def link_string
    octets = @ipv4addr.split('.')
    octets[3]=octets[3].to_i
    otheraddress = case @ipv4prefix
                   when /\/31$/
                     octets[3] ^= 1
                     "link(%s,%s,1) %% inferred from %s" % [ @ipv4addr, octets.join("."), @ipv4prefix   ] 
                   when /\/30$/
                     octets[3] ^= 3
                     octets.join(".")
                     "link(%s,%s,1) %% inferred from %s" % [ @ipv4addr, octets.join("."), @ipv4prefix  ]
                   when /\/29$/
                     range_start = octets[3] + 1
                     range_end = range_start | 7 - 1 
                     ( range_start .. range_end ).to_a.map { |last|
        octets[3] = last
        "link(%s,%s,1) %% inferred from %s" % [ @ipv4addr, octets.join("."), @ipv4prefix ]
      }
                   else
                     ""
                   end

  end
  def bogon?
    @ipv4addr =~ /^10\./ || @ipv4addr =~ /^192\.168\./ || (@ipv4addr=~ /^172\.(\d\d)\./ && $1.to_i < 32 && $1.to_i >= 16 )
  end
  def loopback?
    @ipv4addr =~ /^127\.0\.0\.1/ 
  end
  def to_s
    if @ipv4addr
      "%s %s" % [ @ipv4prefix, @ipv4addr ] 
    else
      "(not ipv4)"
    end
  end
end


class Interface
  attr_accessor :oper_status, :name, :router, :inpackets, :outpackets
  attr_accessor :addresses
               
  def to_s 
    "%s:%s %s %d %d %s" % [ @router, @name, @oper_status, @inpackets, @outpackets, @addresses.join(', ') ]
  end
  def initialize(parent_router)
    @router = parent_router
    @addresses = [] 
  end
end
