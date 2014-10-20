#!/usr/bin/ruby

require 'socket'

File.open(ARGV[1],"w") { |o|
  File.open(ARGV[0]).each { |ln|
    begin
      o.puts IPSocket.getaddress(ln.chomp!.gsub(/^ */,''))
    rescue
      puts "error on #{ln.chomp!}"
    end
  }
}
