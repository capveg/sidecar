#!/usr/bin/ruby

class Array 
	def chooseN(n)
		@chooseN = (0...n).collect { |i| i}	# init array to [0..N-1]
		top =1	# M!/(M-N)!
		((self.length-n+1)..(self.length)).each { |i|
			top *=i
		}
		bottom =1	# N!
		(1..n).each { |i|
			bottom *=i
		}
		total=(top/bottom)	# M!/((M-N)!*N!)
		$stderr.puts "#{top}/#{bottom} == #{total} total combinations"
		yield self.chooseNarray_by_index,1		# first one is the identity
		(2..total).each { |count|		
			# from http://www.merriampark.com/comb.htm, adapted from (algorithm from Rosen p. 286)
			i = n-1
			while( @chooseN[i] == (self.length - n + i))
				i-=1
			end
			@chooseN[i]+=1
			((i+1)...n).each { |j|		# the third period in '...' means don't include the end
				@chooseN[j]=@chooseN[i]+j=1
			}
			yield self.chooseNarray_by_index,count
		}

	end
	def chooseNarray_by_index	# returns an array that is reordered by the indexes in @chooseN
		@chooseN.collect { |i|
			raise " Nil Value in #{@chooseN.join(',')}" unless i
			raise " Bad Value #{i} :: #{@chooseN.join(',')}" if i >= self.length
			self[i]
		}
	end
end


if __FILE__ == $0
	usageStr="usage: chooseN.rb n file" 
	raise usageStr unless ARGV[0]
	raise usageStr unless ARGV[1]

	File.open(ARGV[1],"r").readlines.chooseN(ARGV[0].to_i) { |a,i|
		#puts "------------------ Perm #{i}"
		File.open(File.basename(ARGV[1])+ "-Choose#{ARGV[0]}-#{i}","w"){ |f|
			a.each { |line|
				f.puts line
			}
		}
	}
end

