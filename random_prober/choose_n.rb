#!/usr/bin/env ruby1.8
require 'shuffle'
puts File.open(ARGV[1]).readlines.quick_shuffle!(10)[0,ARGV[0].to_i]
