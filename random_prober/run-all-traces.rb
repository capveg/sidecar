#!/usr/bin/ruby1.8

require 'run-traces'
require 'progressbar_mixin'
require 'socket'
running = Hash.new

Serverlist = "one_per_site.lst"
Addressfile = "addresses.21.r"
# Addressfile = "working_server.lst"

running_file = File.open("running", "w")
File.open(Serverlist).each_inparallel_progress(200, "") { |host|
  begin
    host.chomp!.gsub!(/^\s*/,'')
    prefix = IPSocket.getaddress(host).gsub(/\.\d+$/, '')
    if running[prefix] == nil then
      running[prefix] = 1
      running_file.puts host
      running_file.flush
      runner(host,Addressfile,true)
    end
  rescue => e
    puts  "Not aborting #{host} on #{e}"
  end
}
    
    
    
    
