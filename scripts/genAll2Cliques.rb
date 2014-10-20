#!/usr/bin/ruby 


$sidecarDir=ENV['SIDECARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"

############## TODO
# 1) Don't send probes to a vantage point that are local to that vantage point
# 2) Clean up vantagepoint testing when there are filtered packets
# 3) make a bunch of the pcap overload messages parsed errors and maybe count them


$: << "#{$sidecarDir}/random_prober"
$: << $libDir
$: << '/usr/local/lib/ruby/1.8'	# really should be there by default, but isn't
begin
	require 'dbi'   # install from http://rubyforge.org/projects/ruby-dbi/; see notes at bottom
rescue LoadError => e
	$stderr.puts "Need to install ruby-dbi from http://rubyforge.org/projects/ruby-dbi"
	$stderr.puts " Read the bottom of the source of ips2ttldistance2db.rb for more info"
	exit1
end

$noScriptroute=true
require 'nspring-utils'
require 'fprogressbar'
require 'ips2ttldistance2db.rb'

data2dlvCmd='data2dlv.pl'
#testfactsCmd='timer 60 test-facts.sh'
testfactsCmd='adaptiveDlv.rb'
dlv2adjCmd='dlv2adj.pl'

debug = ""
#debug= "limit 10"

ip2db=Ips2TTLdistance2db.new
tablename='traces'
dbh = DBI.connect("DBI:Pg:dbname=#{ip2db.databasename};host=#{ip2db.databasehost}", ip2db.databaseuser, ip2db.databasepasswd)
$stderr.puts "Making list of all Ips in #{tablename}"
allIps= dbh.select_all("SELECT distinct src from #{tablename} #{debug}") unless allIps
$stderr.puts "#{allIps.length} Ips found in  #{tablename}"

pb = FastProgressBar.new("cliques",allIps.length*allIps.length)
pb.set(0)


allIps.each{ |ip1|
	allIps.each { |ip2|
		pb.inc
		next unless ip1.to_s < ip2.to_s		# only perform 1 ordering
		base="clique-#{ip1}-#{ip2}"
		next if(Kernel.test(?s,"#{base}.model"))
		Kernel.system("#{data2dlvCmd} -clique #{ip1} #{ip2} >  #{base}.dlv") unless(Kernel.test(?s,"#{base}.dlv"))
		Kernel.system("#{testfactsCmd} #{base}.dlv  2>&1 > #{base}.model | grep -v SUCCESS") 
		Kernel.system("#{dlv2adjCmd}  #{base}.model  > /dev/null") 
	}
}
