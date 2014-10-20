#!/usr/bin/ruby

infile = File.open(ARGV[0])

infile.each_line do |line|
  if line =~ /^Source/ or line =~ /^Endhost/
    tokens = line.split(" ")
    ips = tokens[3..-1]
    if ips.size > 1
      puts "---------------"
      ips.each do |ip|
	puts `host #{ip}`
      end
    end
  end
end

