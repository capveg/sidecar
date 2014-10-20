#!/usr/bin/ruby


require 'idvelocity'

ips = Hash.new

File.open(ARGV[0]).each { |line|
   #12.118.116.70    12.118.116.70     1209709104.82477    6874                 Icmp
   (src,dst,time,id,type) = line.chomp.split
   if time != '-'	# if we got a valid response
	   if !ips[src]	# create entry if it doesn't exist
		   ips[src]=IDVelocity.new(src)
	   end
	   ips[src].update(id.to_i,time.to_f)
   end
}

values=Hash.new
ips.each{ |ip,velocity|
	begin
	off,slope,off_err, slope_err, n  = velocity.lineFit()
	s_ci95 = 1.96 * slope_err/Math.sqrt(n) # CI .95 --> 1.96 (from normal distribution chart)

	str= sprintf "%16s off %8f +/- %8f slope %8f +/- %8f %8f n=%d\n" % [
		ip,off,off_err, slope,slope_err, s_ci95, n]
	values[s_ci95]=str
	rescue IDVelocityException => e
		#$stderr.puts "Skipping #{ip} -- #{e}"
	end
}

values.keys.sort.each{ |key|
	puts values[key]
}
