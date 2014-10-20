#!/usr/bin/ruby

Unknown = File.new("pairs-unknown-2", 'w+')
Alias = File.new("pairs-alias-2", 'w+')
Not = File.new("pairs-not-2", 'w+')

file = ARGV[0] || "aliases-2nd-run"

IO.foreach(file) do |line|
  tokens = line.split
  case tokens[3]
  when 'UNKNOWN.'
    Unknown.puts "%s %s" % tokens[0, 2]
  when 'ALIAS!'
    if tokens[4] != "name:"
      Alias.puts "%s %s" % tokens[0, 2]
    end
  when 'NOT'
    Not.puts "%s %s" % tokens[0, 2]
  else
    puts tokens[3]
  end

end

Unknown.close
Alias.close
Not.close
