#!/usr/bin/ruby1.8 -w

require 'shuffle'

$:.push("/home/nspring/wetherall/scriptroute/planetlab")

require 'plab-configuration'
assert_okay_to_ssh

def runner(hostname, address_file, dry=true) 
  randomizedAddressFile = "/tmp/#{address_file}.rand"
  File.open(randomizedAddressFile, "w") { |a|
    # hte lines already have \n's, no join("\n") needed.
    a.puts File.open(address_file).readlines.quick_shuffle!(10,false).join
  }
  rsync(hostname, 
    [ randomizedAddressFile, "find_working_addresses.sr" ].join(" "), "")
  
  ssh(hostname, "./find_working_addresses.sr -i #{address_file}.rand -o #{address_file}.r")
  
  command = "scp '#{UserName}@#{hostname}:#{address_file}.r*' ."
  Kernel.system(command)
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
  ],
  "")

if($Address_file == "") then
  puts "please set the address file"
  c.usage
  exit 1
end

runner($Hostname, $Address_file, true)

end
