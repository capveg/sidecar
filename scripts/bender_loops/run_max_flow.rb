#!/usr/bin/ruby

require '/home/capveg/nspring/nspring-ally-stuff/progressbar_mixin.rb'

class Edge
  attr_reader :capacity

  def initialize(cap)
    @capacity = cap
  end
end

class Node
  attr_reader :name

  def initialize(name)
    @name = $node_counter
    $node_counter += 1
  end
end

$nodes = Hash.new
$edges = Hash.new
$node_counter = 0

fname = (ARGV[0] == nil) ? "example1" : ARGV[0]

infile = File.new(fname)
infile.each_line do |line|

  line =~ /^(.*) (.*)/

  if ($1 != $2)
    if ($nodes[$1+"_in"] == nil)
      $nodes[$1+"_in"] = Node.new($1+"_in")
      $nodes[$1+"_out"] = Node.new($1+"_out")
      $edges[$1+"_in"] = Hash[$1+"_out", Edge.new(1)]
      $edges[$1+"_out"] = Hash.new
    end
    if ($nodes[$2+"_in"] == nil)
      $nodes[$2+"_in"] = Node.new($2+"_in")
      $nodes[$2+"_out"] = Node.new($2+"_out")
      $edges[$2+"_in"] = Hash[$2+"_out", Edge.new(1)]
      $edges[$2+"_out"] = Hash.new
    end

    $edges[$1+"_out"][$2+"_in"] = Edge.new(1)
#    $edges[$2+"_in"][$1+"_out"] = Edge.new(0)

    $edges[$2+"_out"][$1+"_in"] = Edge.new(1)
#    $edges[$1+"_in"][$2+"_out"] = Edge.new(0)
  end
end

num_edges = 0
$edges.each_key do |k1|
  $edges[k1].each_key do |k2|
    num_edges += 1
  end
end

count = 0

all_ASes = Array.new

$nodes.each_key do |k|
  if k =~ /^(AS\d+)_out/ # or k =~ /^(E\d+)_out/ or k =~ /^(S\d+)_out/
    all_ASes << $1
  end
end
num_ASes = all_ASes.size

$stderr.puts num_ASes

hi_pr = IO.popen("/home/bender/3.6/hi_pr", "r+")
hi_pr.puts "p max #{$nodes.size} #{num_edges}"
hi_pr.puts "n 0 s"
hi_pr.puts "n 0 t"

$edges.each_key do |k1|
  $edges[k1].each_key do |k2|
    hi_pr.puts "a #{$nodes[k1].name} #{$nodes[k2].name} 1"
  end
end

hi_pr.puts ""
li = hi_pr.gets

(0..num_ASes-1).to_a.each_progress do |src_ind|
  src = all_ASes[src_ind] + "_out"
  (src_ind+1).upto(num_ASes-1) do |dst_ind|
    dst = all_ASes[dst_ind] + "_in"
    hi_pr.puts "#{$nodes[src].name} #{$nodes[dst].name}"
    li = hi_pr.gets
    puts li
  end
end




=begin

(0..num_ASes-1).to_a.each_progress do |src_ind|
#0.upto(num_ASes-1) do |src_ind|
  src = all_ASes[src_ind] + "_out"

#  count += 1
#  $stderr.puts count.to_s + " " + src

  hi_pr = IO.popen("/home/bender/3.6/hi_pr", "r+")
  hi_pr.puts "p max #{$nodes.size} #{num_edges}"
  hi_pr.puts "n #{$nodes[src].name} s"
  hi_pr.puts "n #{$nodes[src].name} t"

  $edges.each_key do |k1|
    $edges[k1].each_key do |k2|
      hi_pr.puts "a #{$nodes[k1].name} #{$nodes[k2].name} 1"
    end
  end

  hi_pr.puts ""
  li = hi_pr.gets

  (src_ind+1).upto(num_ASes-1) do |dst_ind|
    dst = all_ASes[dst_ind] + "_in"
    hi_pr.puts $nodes[dst].name
    li = hi_pr.gets
#    $stderr.puts dst_ind if dst_ind % 100 == 0
#    puts "#{src} to #{dst} = #{li}"
    puts li
  end
end

=end
