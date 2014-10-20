#!/usr/bin/ruby

def usage(str=nil)
	$stderr.puts str if str
	$stderr.puts "usage: resolve-conflict-by-vote.rb foo.conflict-debug"
end

class Conflict
	def Conflict.resolveFile(fileN)	
		File.open(fileN).each { |line|
			# link(ip213_248_80_244,ip213_248_86_49,1) 7 ally(ip213_248_80_244,ip213_248_86_49) 5 \
			# (./clique-193.167.182.132-64.151.112.20.model;./clique-192.38.109.143-64.151.112.20.model;./clique-128.232.103.201-64.151.112.20.model; \
			# 	./clique-129.12.3.75-64.151.112.20.model;./clique-128.232.103.203-64.151.112.20.model;./clique-192.16.125.12-64.151.112.20.model;\ 
			# 	./clique-192.38.109.144-64.151.112.20.model) \
 			# ( ./clique-193.144.21.131-64.151.112.20.model;./clique-193.167.182.130-64.151.112.20.model;./clique-129.12.3.74-64.151.112.20.model;\
			# 	./clique-193.167.187.188-64.151.112.20.model;./clique-193.6.20.5-64.151.112.20.model)
			 link, linkC,ally,allyC, linkList, allyList   = line.split

			allyVotes = Conflict.calcVote(allyList)
			linkVotes = Conflict.calcVote(linkList)

			if allyVotes > linkVotes
				puts "#{ally}. % #{allyVotes.to_f/(allyVotes+linkVotes)}% #{allyVotes} / #{linkVotes}"
			elsif linkVotes > allyVotes
				puts "#{link}. % #{linkVotes.to_f/(allyVotes+linkVotes)}% #{linkVotes} / #{allyVotes}"
			else
				puts "% TIE #{ally} #{linkVotes.to_f/(allyVotes+linkVotes)}% #{linkVotes} / #{allyVotes}"
			end
		}
	end
	def Conflict.calcVote(list)
		### Vote == Min(unique sources, unique dests)
		srcL = Hash.new
		dstL = Hash.new
		list.gsub(/[();]/,' ').split.each { |trace|
			# ./clique-193.167.187.188-64.151.112.20.model
			match = /.\/\w+-([\d\.]+)-([\d\.]+)\.model/.match(trace)
			if match 
				srcL[match[1]]=1
				dstL[match[2]]=1
			else
				$stderr.puts "Unparsed filename '#{trace}'"
			end
		}

		return srcL.length<dstL.length ? srcL.length : dstL.length
	end
end

if __FILE__ == $0
	usage unless ARGV[0]

	Conflict.resolveFile(ARGV[0])

end


