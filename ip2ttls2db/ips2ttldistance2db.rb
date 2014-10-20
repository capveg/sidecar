#!/usr/bin/ruby 
# 	1) takes a txt file of ip addresses, 1 per line
# 	2) queries for $vantages scriptroute vantages points from scriptroute
#	3) foreach vantage point, foreach ip address
#		3a) run sr-getTTLdistance.rb remotely from vantage point
#	4) enter all info into a DB via DBI (http://ruby-dbi.rubyforge.org/index.html#synopsis)

$sidecarDir=ENV['SIDCARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar" 
$libDir="#{$sidecarDir}/ip2ttls2db"

############## TODO
# 1) Don't send probes to a vantage point that are local to that vantage point
# 2) Clean up vantagepoint testing when there are filtered packets
# 3) make a bunch of the pcap overload messages parsed errors and maybe count them


$: << "#{$sidecarDir}/random_prober"
$: << "#{$sidecarDir}/scripts"
$: << $libDir
begin 
	require 'dbi'	# install from http://rubyforge.org/projects/ruby-dbi/; see notes at bottom
	rescue LoadError => e
		$stderr.puts "Need to install ruby-dbi from http://rubyforge.org/projects/ruby-dbi" 
		$stderr.puts " Read the bottom of the source of ips2ttldistance2db.rb for more info"
		exit1 
end

if($noScriptroute==nil)
	begin
		require 'undns'
		rescue LoadError => e
			$stderr.puts "Need to install undns for this script to work"
			$stderr.puts "run `make undns` from the base directory Makefile to build and install"
			exit
	end
	require 'srclient'
	require 'scriptroute/ally'
end
require "nspring-utils"


class Ips2TTLdistance2db
	attr_accessor :vantages,:databasename,:databaseuser,:databasepasswd,:databasehost

def initialize
	# parameters
	#@nVantages=30
	@nVantages=-1	# no limit, by default; data seems to show that we need 25+ common responses to make this work
	@vantages=nil
	@ipsPerChunk=100
	@ResolveVantages=false
	@logfile=nil
	@logfilename=nil
	@base=nil

	# DB constants
	@databasename='capveg'
	@databaseuser='capveg'
	@databasepasswd='dataentrysux'
	@databasehost='scriptroute.cs.umd.edu'

	# other constants
	@randomizeCmd="#{$sidecarDir}/scripts/randomize"
	@getTTLdistanceCmd="#{$libDir}/sr-getTTLdistance.rb"
	# blacklisted prefixes, in addition to those from scriptroute
	#	should probably move to a file somewhere
	@blacklistPrefixes= [ 
		# clear things that should not be probed
		"0.0.0.0/32 ip",	
		"10.0.0.0/8 ip", 
		"192.168.0/16 ip", 
		"172.16.0.0/12 ip",
		"224.0.0.0/4 ip" ,
		# verizon complaint about TCP, PL#20992,PL#21000
		# not clearly in violation of http://global.mci.com/terms/a_u_p, but whatever
		"63.65.130.45/32 tcp",
		"129.250.9.70/32 tcp",
		"146.188.5.93/32 tcp",
		"146.188.8.162/32 tcp",
		"146.188.8.166/32 tcp",
		"146.188.15.229/32 tcp",
		"154.54.12.250/32 tcp",
		"208.175.172.170/32 tcp",
		]
	
end



def getVantages
	#get list of random vantage points from scriptroute
	possible_vantages = ScriptrouteClient.sitelist
	self.log "Total possible vantages: #{possible_vantages.length}"
	possible_vantages.each { |vantage|	# remove servers in the same /16
		serveraddr =  Resolv.getaddress(vantage)	
		serverprefix = IPAddr.new(serveraddr).mask("255.255.0.0") # choose servers in different /16's
		possible_vantages.delete_if { |srv| serverprefix.include?(IPAddr.new(Resolv.getaddress(srv))) }
	}
	self.log "Slash16 distinct possible vantages: #{possible_vantages.length}"
	tmpvantages=Array.new
	possible_vantages.each_inparallel_progress(possible_vantages.length,"testing vantages",false){|vantage|
		begin
		udp=tcp=icmp=-4
		# try to probe scriptroute.cs.umd.edu 3 times and take the best/highest ttl response as representative
		ScriptrouteClient.new(vantage).query_file(@getTTLdistanceCmd,["128.8.126.104"]*3).each { |line|
			# 128.8.126.104              Udp  -1 -2.000000 -2.000000       Tcp  63 0.000263 -1.000000      Icmp  63 0.000509 -1.000000
			tokens=line.split
			if  tokens[0] =~ /[\d\.]+/ && 	# for some reason, the regexp broke :-(
					tokens[1]=="Udp" &&
					tokens[5]=="Tcp" &&
					tokens[9]=="Icmp" 
				udptmp,udpR = tokens[2].split(/:/)
				tcptmp,tcpR = tokens[6].split(/:/)
				icmptmp,icmpR = tokens[10].split(/:/)
				udp =  [udp,udptmp.to_i].max unless udpR
				tcp = [tcp,tcptmp.to_i].max unless tcpR
				icmp = [icmp,icmptmp.to_i].max unless icmpR
			else
				self.log "Unparsed response from vantage #{vantage} during test: #{line}"
			end
			# after 3 tries... did we get valid responses from everything?
			#	this ASSUMES linux/endhost behavior that startTTL=64 which means
			#	that any TTL>64 did not come from scriptroute
			if ( (0..64).include?(udp.to_i) && (0..64).include?(tcp.to_i) && (0..64).include?(icmp.to_i))
				tmpvantages.push(vantage)	# this is a good vantage point
			else
				self.log("Rejecting potential vantage #{vantage}: udp='#{udp}' tcp='#{tcp}' icmp='#{icmp}'")
			end
		}
		rescue Timeout::Error => e
			self.log "timed out talking to #{vantage} during test: #{e}, not retrying these ips."
		rescue Exception => e
			self.log "Got unknown exception on vantage during test #{vantage}: #{e}"
		end
	}
	possible_vantages=tmpvantages
	self.log "Viable possible vantages: #{possible_vantages.length}"
	possible_vantages.shuffle!.sort!	# shuffle up the server list
	if(@nVantages>0)
		@vantages=possible_vantages[0..(@nVantages-1)]
	else
		@vantages=possible_vantages
	end
	self.log "Vantages (#{@vantages.length}): %s" % [ @vantages.map { |svr|
		if @ResolveVantages
			begin
				Resolv.getname(svr)
				rescue Resolv::ResolvError
					svr
			end
		else
				svr
		end
	}.join(", ") ]

	if @vantages.length ==0 
		self.log("No possible vantages!!! -- exiting")
		exit 1
	end
end

def process_chunk_from_vantage(q,vantage)
	self.log "process_chunk_from_vantage: #{vantage}:: #{q.join(',')}" if $VERBOSE
	dbh = DBI.connect("DBI:Pg:dbname=#{@databasename};host=#{@databasehost}", @databaseuser, @databasepasswd)
	#  INSERT INTO people VALUES ('Euler', 'Leonhard', 248, NULL, 58, 'M')
	sth = dbh.prepare("INSERT INTO #{@tablename} (vantage,ip," +
			"udp,udpr,udprtt,udptscrtt,"+
			"tcp,tcpR,tcpRtt,tcpTscRtt,"+
			"icmp,icmpR,icmpRtt,icmpTscRtt) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?)")
	
	ScriptrouteClient.new(vantage).query_file(@getTTLdistanceCmd,q).each { |line|
		# 12.108.127.129             Udp   -        Tcp 235       Icmp 235
		tokens=line.split

		if  tokens[0] =~ /[\d\.]+/ && 
				tokens[1]=="Udp" &&
				tokens[5]=="Tcp" &&
				tokens[9]=="Icmp" 
			#$stderr.puts "Processing #{line}"
			udp,udpR =  tokens[2].split(/:/);
			udpRtt  = tokens[3]
			udpTscRtt  = tokens[4]
			tcp,tcpR =  tokens[6].split(/:/);
			tcpRtt  = tokens[3]
			tcpTscRtt  = tokens[4]
			icmp,icmpR = tokens[10].split(/:/);
			icmpRtt  = tokens[3]
			icmpTscRtt  = tokens[4]
			udpR='-' unless udpR
			tcpR='-' unless tcpR
			icmpR='-' unless icmpR
			sth.execute(vantage,tokens[0],udp,udpR,udpRtt,udpTscRtt,tcp,tcpR,tcpRtt,tcpTscRtt,icmp,icmpR,icmpRtt,icmpTscRtt)
		else
			self.log "Unparsed response from vantage #{vantage}: #{line}"
		end
	}
	sth.finish	
	dbh.commit # tell the db to commit/finish/flush
	#rescue DBI::DatabaseError => e
		#puts "DBI Error code: #{e.err}"
		#puts "Error message: #{e.errstr}"
		#exit(1)
	rescue Timeout::Error => e
		self.log "timed out talking to #{vantage}: #{e}, not retrying these ips."
	#rescue Exception => e
	#	self.log "Got unknown exception on vantage #{vantage}: #{e}"
	ensure
		# disconnect from server, no matter what
		dbh.disconnect if dbh
end

def log(str)
	@logfilename = @base+".log" unless @logfilename
	@logfile=File.open(@logfilename,"w+") unless @logfile
	@logfile.puts str
	$stderr.puts str
end

def makegoodIPList(file,goodIpFile)
	nIPs=0
	nrejectIPs=0
	makeBlackList($libDir+"/blacklist.dat")
	Undns.origins_init($libDir+"/blacklist.dat")	# load blacklist
	File.open(goodIpFile,File::CREAT|File::EXCL|File::RDWR) { |out|
		File.open(file).each{ |line|
			line.chomp!
			if Undns.origin_for_address_str(line) == 0
				out.puts line 
				nIPs+=1
			else
				nrejectIPs+=1
			end
		}
	}
	self.log "#{nrejectIPs+nIPs} Total Ips: #{nrejectIPs} rejected"
	return nIPs
end

def makeBlackList(blacklist)
	# snag blacklist from scriptroute
	Kernel.system("wget -O #{blacklist} http://www.scriptroute.org/blacklist")
	out=File.open(blacklist,"a")
	out.puts "# add our own local blacklist info"
	@blacklistPrefixes.each{  |line|
		out.puts "#{line} # capveg"
	}
	out.close
	# remap ip/tcp/udp/icmp to filter code 7/1/2/4 
	Kernel.system("perl -pi -e 's/ ip / 7 /g; s/ tcp / 1 /g; s/ udp / 2 /g; s/ icmp / 4 /g' #{blacklist}")
	
end

def testIpFilter	# does the ip filter in makegoodIPList() actually work?
	$stderr.puts "Testing the Undns Ip Filter"
	makeBlackList($libDir+"/blacklist.dat")
	Undns.origins_init($libDir+"/blacklist.dat")
	raise "Failed found test for 69.238.232.38" unless Undns.origin_for_address_str("69.238.232.38") ==7
	raise "Failed not found test for 128.8.128.118" unless Undns.origin_for_address_str("128.8.128.118") ==0
	$stderr.puts "Undns Ip Filter: passed"
end

def process(file)	# where all the magic happens
	@base=File.basename(file) unless @base
	getVantages unless @vantages	# get vantage points if we need them
	###################################
	### Step 1: remove unwanted ips and randomize ip list foreach vantage point: so we don't all hit them at the same time
	#	this is (diskspace and time) expensive and we should find some cool Number Theoretic alg
	# 
	goodIpFile="tmp-#{File.basename(file)}.#{$$}.good" 
	nIPs=makegoodIPList(file,goodIpFile)
	
	self.log "Randomize command '#{@randomizeCmd}'"
	@vantages.each_progress("randomizing") { |vantage|	# do NOT do this in parallel unless you want to kill the machine
		Kernel.system( "#{@randomizeCmd} < %s > %s.#{vantage}" % [goodIpFile, goodIpFile])
		raise "Randomization failed for #{goodIpFile}.#{vantage}" unless Kernel::test(?s,"#{goodIpFile}.#{vantage}")
	}

	###################################
	### Step 2: setup DB stuff; for base, create table as a function of the input filename
	@tablename="ttlDB-#{File.basename(file)}".gsub(/\W/,'_') unless @tablename # "foo.x.y!z" => "ttlDB-foo_x_y_z"
	begin
		# connect to the DB server
		dbh = DBI.connect("DBI:Pg:dbname=#{@databasename};host=#{@databasehost}", @databaseuser, @databasepasswd)
		# FIXME :: make this handle existing tables silently and just ignore error
		dbh.do("CREATE TABLE #{@tablename} (" +
		                " vantage char(20), "+
				" ip char(20), "+
				" udp  int, "+
				" udpR  varchar(20), "+
				" udpRtt interval, " +
				" udpTscRtt interval, " +
				" tcp  int, "+
				" tcpR  varchar(20), "+
				" tcpRtt interval, " +
				" tcpTscRtt interval, " +
				" icmp  int, "+
				" icmpR  varchar(20), "+
				" icmpRtt interval, " +
				" icmpTscRtt interval, " +
				" ts timestamp DEFAULT now() "+
				");" )

		dbh.do("CREATE INDEX IDX_#{@tablename} on #{@tablename} (ip)");

		rescue DBI::DatabaseError => e
			if(/ERROR:  relation \S+ already exists/ =~ e.errstr)
				self.log("Table #{@tablename} already exists; continuing")
			else
				puts "Unknown DBI Error code: #{e.err} at #{__FILE__}:#{__LINE__}"
				puts "Error message: #{e.errstr}"
				exit(1)
			end
		ensure
			# disconnect from server, no matter what
			dbh.disconnect if dbh
	end

		

	###################################
	### Step 3: spawn a thread foreach vantage point to run the queries and actually run it
	@vantages.each_inparallel_progress(@vantages.length,"ips",false) { |vantage|
		q=Array.new
		pbar = ProgressBar.new(vantage,nIPs)
		File.open("#{goodIpFile}.#{vantage}").each{ |ip|
			ip.chomp!
			q.push(ip) unless ip == vantage	# don't have a vantage point try to probe itself; scriptroute doesn't like it
			if q.length>=@ipsPerChunk 	# do we have enough ips to send a chunk?
				process_chunk_from_vantage(q,vantage)
				pbar.inc(q.length)
				q = []	# empty array
			end
		}
		if q.length> 0
		begin
			process_chunk_from_vantage(q,vantage) 
			rescue Exception =>e
				self.log "Exception processing #{vantage}: #{e}, not retrying these ips."
			ensure
				pbar.inc(q.length)
		end
		end
		File.unlink("#{goodIpFile}.#{vantage}")
	}
	rescue Exception =>e
		self.log "Exception processing all vantages -- weird late error!: #{e}, not retrying these ips."
	ensure
		File.unlink(goodIpFile)
end	# end of Ips2TTLdistance2db.processs
end 	# end Class Ips2TTLdistance2db

if __FILE__ == $0 
	raise "Usage: #{$0} list_of_ips" unless(ARGV[0])
	thinger = Ips2TTLdistance2db.new
	#thinger.testIpFilter	# uncomment to test filter code
	# muck with any args here, but defaults seem good
	#thinger.vantages=["204.123.28.56"] # just one vantage point for testing
	thinger.process(ARGV[0])
end



################# Startup/Setup Instructions
# sudo yum install postgresql postgresql-devel
# wget http://ruby.scripting.ca/postgres/archive/ruby-postgres-0.7.1.tar.gz
# ruby extconf.rb
# sudo make install
# ruby-dbi install instructions
# 1) grab http://rubyforge.org/frs/download.php/12368/dbi-0.1.1.tar.gz, untar
# 2) ruby setup.rb config --with=dbi,dbd_pg --rb-dir=/fs/sidecar/scripts/ruby --so-dir=/fs/sidecar/scripts/ruby
# 3) ruby setup.rb setup
# 4) sudo ruby setup.rb install
