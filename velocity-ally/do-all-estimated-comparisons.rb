#!/usr/bin/ruby

USAGE = <<EOF
USAGE: compare-estimated-line-with-data.rb <file with data points> <file with line estimate>
EOF

if ARGV.size != 2
  puts USAGE
  exit
end

MAX_ID = 2**16

# points: key is an IP, values is an array of [time, ipid] pairs
points = Hash.new

count = 0

IO.foreach(ARGV[0]) do |line|

  count +1
  puts "-" if (count % 10000) == 0

  tokens = line.split
  next if tokens[2] == '-' or tokens[3] == '-'
  ip = tokens[0]
  t = tokens[2].to_f
  ipid = tokens[3].to_f

  arr = [t, ipid]
  points[ip] ||= Array.new
  points[ip] << arr
end

outf = File.new("bugger", 'w+')

IO.foreach(ARGV[1]) do |line|
  tokens = line.split
  ip = tokens[0]
  yint = tokens[2].to_f
  slope = tokens[6].to_f

  error = 0.0
  next unless points[ip]
  points[ip].each do |time, ipid|
    estimate = (slope*time + yint) % MAX_ID
    error += (ipid - estimate)**2
  end
  error /= points[ip].size

  outf.puts "%10f %10f" % [slope, error]

end

outf.close
