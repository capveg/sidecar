#!/usr/bin/ruby1.8 -w

require 'shuffle'

$:.push("/home/nspring/wetherall/scriptroute/planetlab")

require 'plab-configuration'
assert_okay_to_ssh

def execute(hostname, remote_addr_filename, destdir, really) 
  sshthread = Thread.new {
    ssh(hostname, "./collectTraces.rb #{really ? "" : "-n"} #{remote_addr_filename}")
  }
  while !sshthread.join(60*30) do # try to join for 30 mins, then enter the loop.  else (we reaped) harvest final.
    ssh(hostname, "bzip2 -f -k *-#{remote_addr_filename}.trc") or return false 
    Kernel.system("scp '#{UserName}@#{hostname}:*-#{remote_addr_filename}.trc.bz2' #{destdir}/#{hostname}.trc.bz2") or return false
  end
  return true
end

def runner(hostname, address_file, really=false) 
  remote_addr_filename = File.basename(address_file)
  # ssh(hostname, "rm -f *-#{remote_addr_filename}.trc*")
  randomizedAddressFile = "/tmp/#{remote_addr_filename}-#{hostname}"
  destdir = "/var/autofs/hosts/tito/nspring/#{remote_addr_filename}"
  `mkdir -p #{destdir}`
  File.open(randomizedAddressFile, "w") { |a|
    # hte lines already have \n's, no join("\n") needed.
    # remove the latency samples if present. 
    a.puts [ 
      File.open(address_file).readlines.map { |ln| ln.gsub!(/ .*$/,'') } + 
      File.open("working_server.addr").readlines 
    ].quick_shuffle!(10,false).join
  }
  rsync(hostname, 
    [ randomizedAddressFile, "collectTraces.rb", 
      "progressbar_mixin.rb", "progressbar.rb", 
      "krishna-servers",
      "rockettrace.sru" ].join(" "), "")
  
  ssh(hostname, "mv #{File.basename(randomizedAddressFile)} #{remote_addr_filename}")

  execute(hostname, remote_addr_filename, destdir, really) or raise "failed early."
  while( ! ssh(hostname, "bzip2 -f *-#{remote_addr_filename}.trc") ) do
    puts "blocking 2 minutes on #{hostname} due to apparent failure."
    sleep(120)
    execute(hostname, remote_addr_filename, destdir, really)
  end
    
  
  puts "scp '#{UserName}@#{hostname}:*-#{remote_addr_filename}.trc.bz2' #{destdir}/#{hostname}.trc.bz2"
  Kernel.system("scp '#{UserName}@#{hostname}:*-#{remote_addr_filename}.trc.bz2' #{destdir}/#{hostname}.trc.bz2")
end

if __FILE__ == $0 then
  require 'scriptroute/commando'

c = Commando.new(ARGV,  # allows substitution by srclient.rb
  [ CommandoVar.new( [ "-a", "--address-file" ], 
      "which file has the list of addresses to probe" , 
      :$Address_file, ""),
    CommandoVar.new( [ "-h", "--host" ], 
      "the name of the planetlab host to run traces from" , 
      :$Hostname, "planetlab01.cs.washington.edu"),
    CommandoVar.new( [ "-r", "--really" ], 
      "don't mess around with echo.  do it.",
      :$Really, false),
  ],
  "")

if($Address_file == "") then
  puts "please set the address file"
  c.usage
  exit 1
end

runner($Hostname, $Address_file, $Really)

end
