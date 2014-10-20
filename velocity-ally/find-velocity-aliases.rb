#!/usr/bin/ruby

MODE = :find

class Velo

  attr_reader :ip

  def initialize(ip, int, slope, n)
    @ip = ip
    @int = int
    @slope = slope
    n =~ /(\d+)/
    @n = $1
  end

  def match?(slope, int)
    if (slope - @slope).abs < 0.05*slope.abs
      if (int - @int).abs < 100
	return true
      end
    end
  end
  def compErr(slope,int)
	s  = slope - @slope
	i  = int - @int
	Math.sqrt((s*s)+(i*i))
  end
end

velos = Array.new

modulus = 2**16

# added by capveg
errorsEntries = Hash.new

IO.foreach(ARGV[0]) do |line|
  tokens = line.split
  ip = tokens[0]
  int = tokens[2].to_f.to_i % modulus
  int_err = tokens[4].to_f
  slope = tokens[6].to_f
  slope_err = tokens[8].to_f
  n = tokens[9]

  puts "#{int} #{slope}" if MODE == :xy


  skip = false
#  if int_err.abs > 0.1*int.abs
#    puts "intercept error too big: #{int_err} outweighs #{int}"
#    skip = true
#  end
  if slope_err.abs > 0.1*slope.abs
#    puts "slope error too big: #{slope_err} outweighs #{slope}"
    skip = true
  end
  next if skip

  velos.each do |velo|
    if velo.match?(slope, int)
      puts "#{ip} #{velo.ip}" if MODE == :find
    end
    # added capveg
    err = velo.compErr(slope, int)
    errorsEntries[err] = "#{err} #{ip} #{velo.ip}"
  end

  velos << Velo.new(ip, int, slope, n)
end

#added capveg
errors = File.open(ARGV[0]+".errors","w+")
errorsEntries.keys.sort.each { |k|
	errors.puts errorsEntries[k]
}
errors.close


