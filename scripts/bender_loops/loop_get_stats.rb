#!/usr/bin/ruby -w

OCTETS_TO_USE = 2

# IP pair to filename
def ip2f(src, dst)
  "/home/bender/swork/sidecar/data/#{src}/data-#{src},0-#{dst},33434"
end

# sort and print hash
def ph(hash)
  hash.sort { |a, b| a[1]<=>b[1]}.each { |a| puts "#{a[0]} : #{a[1]}"}
end

def subnet(ip)
  ip.split('.')[0..(OCTETS_TO_USE-1)].join('.')
end

by_src = Hash.new(0)
by_dst = Hash.new(0)
by_src_as = Hash.new(0)
by_dst_as = Hash.new(0)
in_loop = Hash.new(0)

origin = IO.popen("/home/bender/swork/undns/originForIP", "r+")

IO.foreach("confirmed") do |line1|
  (src, dst) = line1.split

  by_src[subnet(src)] += 1
  by_dst[subnet(dst)] += 1

  origin.puts src
  as = origin.gets.chomp
  by_src_as[as] +=1

  origin.puts dst
  as = origin.gets.chomp
  by_dst_as[as] += 1

  this_trace = Hash.new(0)
  IO.foreach(ip2f(src, dst)) do |line2|
    next if line2 =~ /\#/ or line2 =~ /RR/
    line2 =~ /from ([^ ]*)/
    this_trace[$1] += 1
  end

  this_trace.each do |k, v|
    if v > 1  # if IP is in a loop
      in_loop[k] += 1
    end
  end
end

#puts "sources"
#ph by_src
#puts "dests"
#ph by_dst

#puts "src as"
#ph by_src_as
#puts "dst as"
#ph by_dst_as

# { AS => number of traces where any router in AS is in a loop }
repeated_routers_by_as = Hash.new(0)
# { AS => number of routers in AS that appear in loops }
unique_routers_by_as = Hash.new(0)

unique_routers = 0
repeated_routers = 0

in_loop.each do |k, v|

  unique_routers += 1
  repeated_routers += v

  origin.puts k
  as = origin.gets.chomp
  repeated_routers_by_as[as] += v
  unique_routers_by_as[as] += 1
end

puts "router count by trace"
ph repeated_routers_by_as

repeated_routers = 0
repeated_routers_by_as.each do |k, v|
  repeated_routers += v
end
puts "number of traces: #{repeated_routers}"

puts "router count, unique"
ph unique_routers_by_as

total_routers = 0
unique_routers_by_as.each do |k, v|
  total_routers += v
end
puts "number of routers: #{total_routers}"
