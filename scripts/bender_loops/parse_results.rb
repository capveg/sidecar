#!/usr/bin/ruby

sum = 0
counter = 0

paths = Array.new(123*123)
i = 0

fname = File.open("results-fast")

fname.each_line do |line| 
  if line =~ /disjoint paths from (.*)_out to (.*)_in = (\d+)$/
    next if $1 == $2
    sum += $3.to_i
    counter += 1
    paths[i] = $3
    i += 1
  end
end

paths.collect! {|x| x.to_i}
paths.compact!
paths.sort!

puts "size is " + paths.size.to_s

i = 1.0
outfile = File.open("outfile", "w+")
paths.each do |path|
  break if path == nil
  outfile.puts "#{path}\t#{i/paths.size}"
  i += 1
end


puts "avg of #{counter} nodes is #{sum.to_f / counter}"

gnu = IO.popen("gnuplot -persist", "r+")
gnu.puts "plot 'outfile'"
