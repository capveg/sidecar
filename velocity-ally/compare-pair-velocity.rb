#!/usr/bin/ruby

class Velo

  attr_reader :ip, :int, :slope

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

  def to_s
    "slope = #{@slope}, int = #{@int}"
  end

end

velos = Hash.new

modulus = 2**16

# Fname = "test-responsive-plab-ips.out-reps=2000.slopes"
# Fname = "test-responsive-plab-ips.out.slopes-wrap"
Fname = "dataset_slopes"

IO.foreach(Fname) do |line|
  tokens = line.split
  ip = tokens[0]
  int = tokens[2].to_f.to_i % modulus
  int_err = tokens[4].to_f
  slope = tokens[6].to_f
  slope_err = tokens[8].to_f
  n = tokens[9]

  raise "fuck" if velos[ip]

  velos[ip] = Velo.new(ip, int, slope, n)
end

IO.foreach(ARGV[0]) do |line|
  tokens = line.split
  v1 = velos[tokens[0]]
  v2 = velos[tokens[1]]


  if v1 and v2
#    puts v1
#    puts v2
#    puts "----"
    puts "%10.5f %10d %10s %10s" % [(v1.slope - v2.slope).abs, (v1.int - v2.int).abs, tokens[0], tokens[1]]


  end
end

