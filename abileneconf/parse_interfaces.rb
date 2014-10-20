#!/usr/bin/ruby

$: << "/usr/local/lib/ruby/1.8"

require "rexml/document"
require "rexml/streamlistener"
require "rexml/parsers/sax2parser"
require "rexml/parsers/lightparser"
require "scriptroute/rockettrace"
require "interface"

$aliases = LambdaHash.new( lambda { [] })
$prefixes = LambdaHash.new( lambda { [] })
$better_be_unique = Hash.new

class InterfacesXMLListener 
  include REXML::StreamListener
# receive start_elementkey
# receive textArtist
# receive end_elementkey
# receive start_elementstring
# receive textAnything Box
# receive end_elementstring
# receive text
  def initialize
    @element_type = nil
    @key = nil
    @tag = []
  end
  def receive(x)
    case x[0] 
    when :start_element
      @element_type = x[1];
    when :text
      puts "r text #{@element_type} #{x[1]}"
    when nil
    end
  end
  def start_element(t)
    @element_type = t
  end
  def end_element(t)
  end
  def text(t)
    $stderr.puts "text in %s: %s" % [ @tag.join(':'), t ] if($VERBOSE)
    thisrouter = @tag.detect { |r| r =~ /^router\// }
    if @tag.detect { |v| v == "physical-interface" } then
      case @tag[-1]
      when "name"
        @current_interface.name = t  if @tag[-2] == 'physical-interface' # not the logical names
      when "ifa-local"
        @current_address.ipv4addr = t if t =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
        # $aliases[thisrouter] <<= t if t =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
      when "ifa-destination"
        @current_address.ipv4prefix = t if t =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
        # $prefixes[thisrouter] <<= t if t =~ /\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3}/
      when "oper-status"
        @current_interface.oper_status = t
      when "input-pps"
        @current_interface.inpackets = t
      when "output-pps"
        @current_interface.outpackets = t
      end
    end
  end
  def tag_start( name, attrs) 
    case name
    when "router"
      @tag.push "%s/%s" %  [ name,attrs['name'] ]
    when "interface-information" 
      @tag.push "%s/%s" %  [ name,attrs['name'] ]
    when "physical-interface"
      thisrouter = @tag.detect { |r| r =~ /^router\// }
      @current_interface = Interface.new(thisrouter)
      @tag.push name
    when "interface-address"
      thisrouter = @tag.detect { |r| r =~ /^router\// }
      @current_address = InterfaceAddress.new
      @current_interface.addresses <<= @current_address
      @tag.push name
    else
      @tag.push name
    end
  end
  def tag_end( name ) 
    @tag.pop
    case name
    when "physical-interface"
      if @current_interface.oper_status == "up" then
        # puts @current_interface
        thisrouter = @tag.detect { |r| r =~ /^router\// }
        @current_interface.addresses.each { |a|
          if a.ipv4addr && !a.bogon? && @current_interface.name !~ /^dsc/ && !a.loopback? && a.ipv4addr != "198.32.8.238" then
            $aliases[thisrouter] <<= a.ipv4addr 
            raise "hell: %s is in %s and %s, interface %s" % [ a.ipv4addr, $better_be_unique[a.ipv4addr], thisrouter, @current_interface.name ] if $better_be_unique.has_key?(a.ipv4addr)
            $better_be_unique[a.ipv4addr] = thisrouter
            $prefixes[thisrouter] <<= a.link_string 
          end
        }
      end
    when "interface-address"
      @current_address = nil
    end
  end
end


olist = InterfacesXMLListener.new
orig_p = REXML::Parsers::StreamParser.new(File.open("show_interfaces.xml").read, olist) 
orig_p.parse

o = File.open("human-readable.txt", "w")

$aliases.each { |r,list| 
  o.puts "%s: " % r
  # puts "%s: %s" % [ r, list.join(', ') ] 
  list.sort.each { |a| 
    o.puts "  %s" % a
    list.each { |b| 
      puts "alias(%s,%s,foo) %% %s" % [ a, b, r ] unless (a==b)
    }
  }
}
$prefixes.each { |r,list| 
  puts "%% %s:" % [ r ] 
  list.compact.each { |a|
    puts a
  }
}




