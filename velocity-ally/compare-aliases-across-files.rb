#!/usr/bin/ruby

ip_hash = Hash.new
IO.foreach(ARGV[1]) do |line|
  tokens = line.split
  ip = tokens[0]
  int = tokens[2]
  slope = tokens[6]
  n = tokens[9]
  ip_hash[ip] = [int, slope, n]
end


IO.foreach(ARGV[0]) do |line|
  tokens = line.split
  if tokens[3] == "ALIAS!"
    puts "----"
    x = ip_hash[tokens[0]]
    y = ip_hash[tokens[1]]

    puts tokens[0] + " " + x.join(" - ") if x
    puts tokens[1] + " " + y.join(" - ") if y


  end
end
