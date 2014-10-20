#!/usr/bin/ruby

require '../interface'

rmap = Hash.new

Dir.glob("Out=*").each { |filename|
  interface = nil
  router = filename.gsub(/^Out=/, '')
  rmap[router] = Hash.new
  File.open(filename).map { |ln| ln.gsub(/&nbsp;/,' ').gsub(/<br>/, "\n<br>").split('<br>') }.flatten.each { |ln|
#   if ln=~ /(Loopback\d+)\s+/		# DON'T SKIP LOOPBACK ON CANET -- they use these with real addresses!
#	    interface=nil
#	    puts "Skipping Loopback interface #{$1} on #{filename}"
    if ln=~ /^([\w\/\d\.]+) is Up, line protocol is Up/i then
      interface = $1
    elsif ln=~ /^  Internet address is (\d+\.\d+\.\d+\.\d+)\/(\d+)/ then
      if interface 
	      iface = InterfaceAddress.new
	      iface.ipv4addr = $1
	      iface.ipv4prefix = "%s/%s" % [ $1, $2 ]
	      rmap[router][interface] =  iface
	      interface=nil
      else
	puts "Skipping #{$1} on #{filename} -- no associated interface"
      end
      # "%s/%s" %  [ $1,$2 ]
    elsif ln =~ /Logical interface ([\w\/\d\.-]+) \(Index \d+\)/
      interface = $1
      # next line differs from geant, since these guys do some word-wrapping, putting broadcast on the next line.
    elsif ln =~ /Destination: \d{1,3}\.\d{1,3}(\.\d{1,3}(\.\d{1,3})?)?\/(\d{1,2}), Local: (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
      # rmap[router][interface] = "%s/%s" %  [ $4,$3 ]
      if interface 
	      iface = InterfaceAddress.new
	      iface.ipv4addr = $4
	      iface.ipv4prefix = "%s/%s" % [ $4, $3 ]
	      rmap[router][interface] =  iface
	      interface=nil
      else
	puts "Skipping #{$1} on #{filename} -- no associated interface"
      end
    elsif ln =~ /^\s+Local: (\d{1,3}\.\d{1,3}\.\d{1,3}\.\d{1,3})/
      # rmap[router][interface] = "%s/%s" %  [ $4,$3 ]
      if interface 
	      iface = InterfaceAddress.new
	      iface.ipv4addr = $1
	      iface.ipv4prefix = "%s/%s" % [ $1, 32 ]
	      rmap[router][interface] =  iface
	      interface=nil
      else
	puts "Skipping #{$1} on #{filename} -- no associated interface"
      end
    end
  }
}

nlrfactsfile = File.open('./canet4-facts.dlv', 'w')
rmap.each { |router, ifacehash|
  puts "buiding router map stuff for router: %s" % router
  aliases = [] 
  ifacehash.each { |name, ip|
    puts " %s (%s) %s" % [ ip, name, ip.bogon? ? "bogon" : "" ]
    aliases <<= ip.ipv4addr unless(ip.bogon? or ip.loopback?)
    nlrfactsfile.puts ip.link_string unless (ip.bogon? or ip.loopback?)
  }
  aliases.each { |a|
    aliases.each { |b|
      nlrfactsfile.puts( "alias(%s,%s,foo) %% %s" % [ a, b, router ] ) unless (a==b)
    }
  }
}

          # if a.ipv4addr && !a.bogon? && @current_interface.name !~ /^dsc/ && !a.loopback? && a.ipv4addr != "198.32.8.238" then
            # $aliases[thisrouter] <<= a.ipv4addr 
            # raise "hell: %s is in %s and %s, interface %s" % [ a.ipv4addr, $better_be_unique[a.ipv4addr], thisrouter, @current_interface.name ] if $better_be_unique.has_key?(a.ipv4addr)
            # $better_be_unique[a.ipv4addr] = thisrouter
            # $prefixes[thisrouter] <<= a.link_string 
          # end