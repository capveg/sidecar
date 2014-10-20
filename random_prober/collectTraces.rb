#!/usr/bin/env ruby

$VERBOSE = 1
$prefix = "/net/bogus/exports/disk2/nspring/"
$parallelism = IO.popen("echo 'puts Scriptroute.DaemonConfig[\"ExperimentLimits.total\"]' | srinterpreter -").readlines[0].chomp.to_i / 2
if($parallelism < 10) then
  $parallelism = 10
  $stderr.puts  "WARNING: unable to properly determine reasonable parallelism"
end

require 'progressbar_mixin'
class Array
      include ProgressBar_Mixin
end

#Hostname = `/bin/hostname`.chomp
Hostname = "rocketfuel"
Interpreter = if(ARGV[0] == "-n") then
  # dry run. don't trace, just from the file.
  ARGV.delete_at(0)
  "/bin/echo"
else
  "/usr/bin/srinterpreter"
end

def should_I_wait?
  procInfo = Hash.new
  File.open("/proc/meminfo", 'r').each { |ln|
    k,v = ln.split(':')
    procInfo[k] = v.gsub(/^ */,'').gsub(/ kB.*$/,'')
  }
  # should be at least 3/4 free.  
  (procInfo["SwapFree"].to_f / procInfo["SwapTotal"].to_f) < 0.75
end


trace_filename  = "%s%s-%s.trc" % [ $prefix, Hostname, ARGV[0]]
done = Hash.new
begin
  ( Dir.glob(trace_filename + "*") ).each { |filename|
    File.open(filename, "r").each { |ln|
      if ln =~ /job: (\d+\.\d+\.\d+.\d+)/ then 
        done[$1] = true
      end
    }
  }
rescue => e
  puts "wtf error: " + e
end



File.open(ARGV[0]).each_inparallel_progress($parallelism, Hostname.gsub(/^planet/,''), false, 30) { |addr|
  addr.each {|a| a.chomp! }
  addr.delete_if { |a| done[a] || a == "" } 
  if(addr.length > 0) then
    if should_I_wait? then
      $stderr.puts "%s backing off due to memory pressure" % [ Hostname ]
      while should_I_wait? do
        sleep 180
      end
    end
    if Interpreter != "/bin/echo" then
      o = File.open("%s.tid%d" % [ trace_filename,  Thread.current["index"] ], "a")
      $stdout.reopen(o)
    end
    if ! Kernel.system(Interpreter, "-ud", "./rockettrace.sru", 
        "-q", "1", "-S", "3", "-n", *addr) then
      # possible that we'll take an exception due to address filtering
      # for local subnet or local host; so do the failed ones one
      # at a time.
      addr.each { |a|
        Kernel.system(Interpreter, "-ud", "./rockettrace.sru", 
          "-q", "1", "-S", "3", "-n", a) 
      }
    end
  end
}
