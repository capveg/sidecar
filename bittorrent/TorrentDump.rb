#!/usr/bin/ruby

require "Bencode.rb"

def usage(str="Needs arg")
	STDERR.printf("Error: #{str}\n")
	STDERR.printf("Usage: TorrentDump.rb	foo.torrent\n")
	exit(1)
end

torrent=ARGV[0]

if torrent == nil
	usage()
end

f = File.new(torrent, "r")
torrent_str = f.read() # slurp everything up at once

dict = Bencode.decode(torrent_str)
#Bencode.dump(dict)	# my bad, my bad: don't do that

dict.each { |key,val| 
	next if key == 'info'
	if key == 'creation date'
		puts "Created = #{Time.at(dict['creation date'])}"
	else
		puts "#{key} = #{val}"
	end
}

puts "Info:"
dict['info'].each { |key,val|
	if key == 'pieces'
		nPieces=val.length/20
		puts "	#{key}= #{nPieces}"
	elsif key == 'files'
		puts "	Files:"
		val.each {| d|
			print "\t\t"
			d.each { |k2,v2|
				print "#{k2}=#{v2} "
			}
			print "\n"
		}
	elsif key == 'file'
		puts "	File:"
		print "\t\t"
		val.each { |k2,v2|
			print "#{k2}=#{v2} "
		}
		print "\n"
	else
		puts "	#{key} = #{val}"
	end
}
nPieces=dict['info']['pieces'].length/20
pieceSize=dict['info']['piece length'].to_i
puts "Total Size = #{nPieces} pieces X #{pieceSize} bytes/piece =  #{nPieces*pieceSize} bytes"

