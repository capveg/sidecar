#! /usr/bin/ruby

def color_by_type(router_type)
  case router_type
  when 'A', 'A_RREND'
    '#BBFFBB'
  when 'B', 'B_RREND', 'M_B'
    '#BBFFFF'
  when 'M'
    '#FFBBFF'
  when 'N'
    '#FFBBBB'
  when 'MPLS'
    '#FFFFBB'
  when '', nil
    '#FFFFFF'
  else 
    puts 'unrecognized type %s' % router_type
    '#FF0000'
  end
end

def remove_questionmarks(string) 
  string.gsub(/\?\?(\\n)?/, '')
end

input = "5b.dot"
output = "5bs.dot"
dot_or_neato = 'neato'

File.open(output, "w") { |o|
  File.open(input).each { |ln|
    case ln
    when /^\s*overlap/
      o.puts "overlap=scale"
    when /^\s*node/
      o.puts "node [shape=record,style=filled,width=4];"
    when /\s*"([RS]\d*)(_(\w+))?" \[fillcolor=(\w+),label = "(\{)?[^|]+\s*\| (.*)/
      o.puts '"%s%s" [fillcolor="%s", label = "%s %s' % [ $1, $2, color_by_type($3), $5, remove_questionmarks($6) ]
    else
      o.puts ln
    end
  }
}


system('%s -Tps < %s > %s' % [ dot_or_neato, output, output.gsub(/dot$/, 'eps') ])
system('epstopdf %s'%[output.gsub(/dot$/, 'eps') ])
      
