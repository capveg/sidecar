#!/usr/local/bin/ruby

require "Bencode"
require "net/http"
require "digest/sha1"
require "zlib"
require "timeout"
require "nspring-utils"

nThreads=20
#dumpInterval=60*5	# every 5 minutes, dump the database
dumpInterval=60*1	# every 1 minutes, for testing
StaleDataTime=60*60	# data older then 60 minutes is stale and should be ignored
GetTimeout=30		# timeout after GetTimeout seconds
#verbose=true


#####################################

class DumpTracker
	NumWant = 1000
	Verbose=false
	AdvertizedPort=8080
	def DumpTracker.dump_tracker(torrent_file,lock,database)
		$stderr.puts "	processing #{torrent_file} in thread:#{Thread.current{'index'}}" if Verbose
		status = Timeout::timeout(GetTimeout) {
			f = File.new(torrent_file, "r")
			torrent_str = f.read() # slurp everything up at once
			f.close

			torrent = Bencode.decode(torrent_str)
			return if torrent == nil

			# extract host,port pair
			url = torrent['announce']	# http://torrent.linux.duke.edu:6969/announce
			parts=url.split(/\//)
			host,port = parts[2].split(/:/)
			if port == nil
				port = 80	# set default port if not specified
			end

			# gen info hash
			info_hash = Digest::SHA1.hexdigest(Bencode.encode(torrent['info']))
			info_hash.gsub!(/([0-9a-f][0-9a-f])/,'%\1')	# "deadbeef" --> "%de%ad%be%ef"

			# gen the peer id, Azureus-style (http://wiki.theory.org/BitTorrentSpecification#peer_id)
			peer_id = ""
			'-SC0001-'.each_byte{ |b| peer_id += "%2x" % b }
			hex_chars = ("0".."9").to_a+("a".."f").to_a
			rand_id = ""
			1.upto(40-peer_id.length) { |i| 
				# add two random hex chars to string
				rand_id+=hex_chars[rand(hex_chars.length)]
				}
			peer_id+=rand_id
			peer_id.gsub!(/([0-9a-f][0-9a-f])/,'%\1')
			# gen random request port
			reqport = rand(65535-1025)+1025
			# calc file size
			nPieces=torrent['info']['pieces'].length/20
			pieceSize=torrent['info']['piece length'].to_i
			size=nPieces*pieceSize
			# generate request
			request = "/#{parts[3]}" +
					"?info_hash=#{info_hash}" +
					"&peer_id=#{peer_id}" +
					#"&supportcrypto=1" +
					"&port=#{AdvertizedPort}" +	# use this instead of reqport so we can sidecarprobe inc traffic
					"&azudp=3733" +
					"&uploaded=0" +
					"&downloaded=0" +
					"&left=#{size}" +
					"&event=started" +
					"&numwant=#{NumWant}" +
					"&no_peer_id=1" #+
					#"&compact=1" +
					#"&key=IaXnMnd0"	# key stolen from Azureus session, should prob be random

			#$stderr.puts "Sending GET for #{request} to #{host} on port #{port}" if Verbose
			# actually send request
			#$stderr.puts " 	torrent #{torrent_file} before GET in thread:#{Thread.current['index']}"
			resp = Net::HTTP.get_response(host,request,port)		# make connection, send request
			#$stderr.puts " 	torrent #{torrent_file} after GET in thread:#{Thread.current['index']}"

			return if resp == nil
			case resp
			when Net::HTTPSuccess, Net::HTTPRedirection
				# OK
			else
				#resp.error!
				$stderr.puts "Error connecting to tracker for torrent #{torrent_file}"
				return
			end
			data=resp.body

			if resp['Content-Encoding'] =~/gzip/	# unzip things if necessary
				$stderr.puts "Uncompressing..." if Verbose
				#data = Zlib::Inflate.inflate(data)
				gunzip = IO.popen("gunzip","w+")
				gunzip.write(data)
				gunzip.close_write();
				data =gunzip.read()
				gunzip.close
			end

			dict = Bencode.decode(data)
			return if dict == nil
			if Verbose
				$stderr.puts "-------------"
				$stderr.puts "VERBOSE:resp:"
				resp.each_header { |h|
					$stderr.puts "#{h}"
				}
				$stderr.puts "VERBOSE:data: #{data}"
				Bencode.dump(dict,$stderr)
			end

			lock.synchronize do 	
				if dict['peers'] != nil 
					dict['peers'].each { |p|
						#puts "#{p["ip"]}:#{p["port"]}"
						if database[p["ip"]]== nil		# alloc hash if not exits
							database[p["ip"]]= Hash.new
						end
						database[p["ip"]]["port"]=p["port"];
						database[p["ip"]]["lastseen"]=Time.now
					}
				else
					$stderr.puts "Error: no peers found: #{torrent_file}"
					Bencode.dump(dict,$stderr)
				end
			end
		}
		rescue Timeout::Error => err
			$stderr.puts "TIMEOUT in thread:#{Thread.current['index']}:: #{err}"
		rescue  => err
			$stderr.puts "ERR in thread:#{Thread.current['index']}:: #{err}"
	end
end

#################################
def usage(str="Need to specify torrent")
	STDERR.puts("Error: #{str}")
	STDERR.puts("Usage: TrackerDump.rb  [torrent_file] [-]")
	exit(1)
end

#################################
def dumpDB(filecount,database_lock,database)
	filen="database.#{filecount}"
	count=0
	$stderr.puts "Dumping DB to #{filen} at #{Time.now.asctime}"
	database_lock.synchronize do
		out = File.new(filen,"w")
		database.each_pair{ |ip,h|
			count+=1
			if ((h["lastseen"]+StaleDataTime)<=>Time.now)>0
				out.puts "#{ip}:#{h['port']}	#{h['lastseen'].to_i}"
			else
				database.delete(ip)
			end
		}
		out.close
	end
	$stderr.puts "Done Dumping DB #{count} ips to #{filen} at #{Time.now.asctime}"
	rescue => e
		$stderr.puts "--- Dumper Thread got err=#{e}"
end


#################################
torrent_list = []

ARGV.each{ |arg|
	torrent_list << arg
}

if torrent_list.length < 1
	$stderr.puts "Reading torrents from stdin"
	$stdin.each_line { |line|
		line.chomp!
		#$stderr.puts "adding line '#{line}'"
		torrent_list << line
	}
end
if torrent_list.length < 1
	usage
else
	$stderr.puts "Processing #{torrent_list.length} torrents"
end

# randomize the order we visit the list
torrent_list.shuffle!
	
database_lock = Mutex.new
database = Hash.new	# heh.. "database" :-P

# periodically dump the database to a file
dumperThread = Thread.new {
	filecount=0
	while true
		sleep dumpInterval
		dumpDB(filecount,database_lock,database)
		filecount+=1
	end
}



torrent_list.each_inparallel_progress(nThreads) { |torrent_file|
	DumpTracker.dump_tracker(torrent_file,database_lock,database)
}

dumpDB("final",database_lock,database)
