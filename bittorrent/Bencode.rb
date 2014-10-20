class Bencode
############################################################################
	def Bencode.encode(thing)
		if thing.is_a?(String)
			return "#{thing.length}:#{thing}"
		end
		if thing.is_a?(Fixnum)
			return "i#{thing.to_s}e"
		end
		if thing.is_a?(Bignum)
			return "i#{thing.to_s}e"
		end
		if thing.is_a?(Array)
			line="l"
			thing.each{|e| line+=Bencode.encode(e)}
			return line+"e"
		end
		if thing.is_a?(Hash)
			line="d"
			thing.keys.sort.each { |key| 
				line+=Bencode.encode(key)
				line+=Bencode.encode(thing[key])
			}
			return line+"e"
		end
		puts "Unknown type #{thing.class}\n"
	end
############################################################################
	def Bencode.decode(str)
		val,index=Bencode.decode1(str,0)
		return val
	end
	def Bencode.decode1(str,index)
		if str[index]=='i'[0]			# decode int
			e=str.index('e',index)
			return str[index+1,e-index-1].to_i, e+1
		end
		if str[index]>='0'[0] && str[index]<='9'[0]	# decode string
			colon=str.index(':',index)
			l= str[index,colon].to_i
			return str[colon+1,l], colon+l+1
		end
		if str[index]=='l'[0]	# decode list
			arr= Array.new()
			index+=1
			while str[index]!='e'[0]
				val, index=Bencode.decode1(str,index)
				return nil if val == nil
				arr.push(val)
			end
			return arr,index+1
		end
		if str[index]=='d'[0]	# decode hash/dictionary
			h= Hash.new()
			index+=1
			while str[index]!='e'[0]
				key, index=Bencode.decode1(str,index)
				return nil if key == nil
				val, index=Bencode.decode1(str,index)
				return nil if val == nil
				h[key]=val
			end
			return h,index+1
		end

		puts "Bencode.decode:: Unknown symbol '#{str[index]}' at index #{index} of '#{str[0,index+10]}'\n"
		return nil
	end
############################################# Unittesting#################
	def Bencode.unittest
		puts "Test 1 "+ Bencode.encode("foo")
		puts "Test 2 "+ Bencode.decode(Bencode.encode("foo"))
		str= Bencode.encode(45)
		puts "Test 3 :"+ str + " = " + Bencode.decode(str).to_s
		str= Bencode.encode([ "foo", "bar", 64, "baz"])
		puts "Test 4 "+ str
		puts "Test 5 " 
		Bencode.dump(Bencode.decode(str))
		str= Bencode.encode({ "foo"=>"bar","alpha"=> [ "beta","gamma"], "three"=> 3})
		puts "Test 6 " + str
		puts "Test 7 "
		Bencode.dump(Bencode.decode(str))

		#puts Bencode.encodelist([ "foo", "bar", 64, "baz"])	# deprecated
	end
############################################################################
	def Bencode.dump(thing,file=$stdout)
		Bencode.dump1(thing,0,file)
	end
	def Bencode.dump1(thing,nTabs,file)
		if file == nil
			$stderr.puts "WTF@!? file == nil at #{__FILE__}:#{__LINE__}"
			return nil
		end
		str = "\t"*nTabs
		str = " " if nTabs == 0
		if thing.is_a?(String)
			file.puts str+"string: #{thing}"
			return
		end
		if thing.is_a?(Fixnum)
			file.puts str+"int: #{thing.to_s}"
			return
		end
		if thing.is_a?(Array)
			file.puts str+"List:"
			thing.each{|e| Bencode.dump1(e,nTabs+1,file)}
			return 
		end
		if thing.is_a?(Hash)
			file.puts str+"Hash:"
			thing.each{|key,val| 
				Bencode.dump1(key,nTabs+1,file)
				Bencode.dump1(val,nTabs+2,file)}
			return
		end
		file.puts "Unknown type #{thing.class}\n"
	end
end
