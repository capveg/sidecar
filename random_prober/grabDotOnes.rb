#!/usr/bin/env ruby 

$VERBOSE = 1

require 'socket'
def IPSocket.getaddrinfo(x)
  raise "don't go here."
end
def IPSocket.getaddress(x)
  raise "don't go here."
end

require 'my-ipaddr'
require 'ipaddr'
require 'shuffle'
require 'progressbar_mixin'


# Hackishly comment out Blacklist code and move it to a much faster C prog filter_blacklist
#BlackList = "/etc/scriptroute/blacklist"
#blacklist = File.open(BlackList).map { |line|
#	IPAddr4.new(line.split[0])
#}
#$stderr.puts "Blacklist #{BlackList} read: #{blacklist.size} entries"


class Array 
  include  ProgressBar_Mixin
end
# class Array
  # alias orig_uniq uniq
  # def uniq
    # $stderr.puts "uniquing"
    # r = orig_uniq
    # $stderr.puts "uniqued"
    # r
  # end
# end

Disaggregate = ARGV[0].to_i
raise "need level of disaggregation" unless Disaggregate > 0
output = File.open("addresses.%d.tmp" % Disaggregate, "w")
input = File.open("origins.dat")
input.each_progress("prefixes") { |ln|
  prefix, asn = ln.split
  next if asn.to_i == 65333
  begin 
    base = IPAddr.new(prefix)
    output.puts( (base | 1).host!  )
    base.each_component(Disaggregate) { |i|
#      found=false
#      blacklist.each { |entry|
#      	found = true if entry.include?(i|1)	# filter out stuff in the blacklist
        output.puts( i | 1  )# unless found
      #}
    }
    #  $stderr.puts r.join(" ")
    #output.puts r.join("\n")
  rescue => e
    puts " failed on %s: %s" % [ prefix, e ]
    puts   e.backtrace
  end
}
output.close
# make unique but sort of randomize with the goal being to 
# get good results quickly.
#command = "sort -k3 -t . -u addresses.%d.tmp > addresses.%d" % [ Disaggregate, Disaggregate ]  ## HORRIBLY BROKEN; 
command = "sort -u addresses.%d.tmp > addresses.%d" % [ Disaggregate, Disaggregate ]
Kernel.system(command)
# File.unlink("addresses.%d.tmp" % [Disaggregate])
# quick_shuffle!(5).join("\n")
