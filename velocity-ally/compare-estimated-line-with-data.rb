#!/usr/bin/ruby

USAGE = <<EOF
USAGE: compare-estimated-line-with-data.rb <file with data points> <file with line estimate> <IP>
  IP must appear in both files, obviously
OUTPUT: <IP>.out   -- 3 columns: time      data point at that time      estimate at that time
EOF

# compare-estimated-line-with-data.rb ~capveg/swork/sidecar/velocity-ally/test-responsive-plab-ips.out-reps=2000  test-responsive-plab-ips.out-reps=2000.slopes 193.1.195.138

if ARGV.size != 3
  puts USAGE
  exit
end

EPOCH = 1209708959.56698

MAX_ID = 2**16

IP = ARGV[2]

points = Hash.new

#IO.foreach(ARGV[0]) do |line|
#  tokens = line.split
#  next unless tokens[0] == IP

lines = `grep #{IP} #{ARGV[0]}`.split("\n")

lines.each do |line|
  tokens = line.split
  next if tokens[0] != IP

  next if tokens[2] == '-' or tokens[3] == '-'
  t = tokens[2].to_f - EPOCH
  ipid = tokens[3].to_f
  if points[t]
    puts "huh?  time already exists: #{t}"
  end
  points[t] = ipid
#  puts ipid
end

yint = 0
slope = 0

IO.foreach(ARGV[1]) do |line|
  tokens = line.split
  next unless tokens[0] == IP
  yint = tokens[2].to_f
  slope = tokens[6].to_f
end


puts "yit = #{yint} slope = #{slope}"

fname = IP+".out"
outf = File.new(fname, "w+")

points.keys.sort.each do |time|
  estimate = (slope*time + yint) % MAX_ID
  outf.puts "%10f %10f %10f" % [time, points[time], estimate]
end

outf.close
