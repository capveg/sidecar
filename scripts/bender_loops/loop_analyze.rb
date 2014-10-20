#!/usr/bin/ruby -w

WRITE_TO_FILE = false
Path = "/home/bender/swork/sidecar/data/"

missing_count = 0
small_count = 0
bad_src = 0
loop_count = 0
good_count = 0

missing_hosts = Hash.new("")

known_bad_ips = Hash.new
File.foreach("bad_ips") do |line|
  line =~ /^(.*)\t/
  known_bad_ips[$1] = 1
end

outie = File.open("confirmed", "w+") if WRITE_TO_FILE

Dir['sources/*'].each do |fname|
  src = fname.split('/')[-1]
  IO.foreach(fname) do |dst|
    if known_bad_ips[src] == 1
      bad_src += 1
    else
      dst.chomp!

      # look for results
      data_file = Path + src + "/data-#{src},0-#{dst},33434"
      if not File.exist?(data_file)
        missing_count += 1
#        puts "#{data_file} is missing!"
        missing_hosts[src] += "\n  #{dst}"
      elsif File.size(data_file) < 10
        small_count += 1
#        puts "#{data_file} is too small! (#{File.size(data_file)})"
        missing_hosts[src] += "\n  #{dst}"
      else
        first_line = File.open(data_file).readline
        if first_line =~ /finalstate .*==(\d+)/
          if $1 == "109"
            loop_count += 1
            outie.puts src + " " + dst if WRITE_TO_FILE
          else
            good_count += 1
          end
        else
          puts "some bad mojo: #{first_line}"
          exit
        end
      end
    end
  end
end

outie.close if WRITE_TO_FILE

puts "bad source: #{bad_src}"
puts "missing: #{missing_count}"
puts "small: #{small_count}"
puts "loop: #{loop_count}"
puts "good: #{good_count}"
puts "total: #{missing_count + small_count + good_count + loop_count + bad_src}"

missing_hosts.each_pair do |k, v|
#  puts "\n#{k}#{v}"
end
