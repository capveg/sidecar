#!/usr/bin/ruby

#  psql -h drive -t -c 'select distinct src,dst,resp,ttl from (select * from traces limit 1000) as foo where nrr=-1 order by src,dst,ttl' > test

# 128.208.4.197   | 12.46.129.23    | 128.208.4.100   |   1
# 128.208.4.197   | 12.46.129.23    | 205.175.110.17  |   2
# 128.208.4.197   | 12.46.129.23    | 205.175.103.157 |   3
# 128.208.4.197   | 12.46.129.23    | 205.175.103.10  |   4
# 128.208.4.197   | 12.46.129.23    | 209.124.176.5   |   5
# 128.208.4.197   | 12.46.129.23    | 209.124.179.41  |   6
# 128.208.4.197   | 12.46.129.23    | 12.127.6.193    |   7
# 128.208.4.197   | 12.46.129.23    | 12.122.12.113   |   8
# 128.208.4.197   | 12.46.129.23    | 12.122.11.90    |   9
# 128.208.4.197   | 12.46.129.23    | 12.123.213.153  |  10
# 128.208.4.197   | 12.46.129.23    | 12.124.44.30    |  11
# 128.208.4.197   | 35.9.27.27      | 128.208.4.100   |   1
# 128.208.4.197   | 35.9.27.27      | 205.175.110.17  |   2
# 128.208.4.197   | 35.9.27.27      | 205.175.103.157 |   3
# 128.208.4.197   | 35.9.27.27      | 205.175.103.10  |   4
# 128.208.4.197   | 35.9.27.27      | 209.124.176.12  |   5
# 128.208.4.197   | 35.9.27.27      | 209.124.179.46  |   6
# 128.208.4.197   | 35.9.27.27      | 216.24.186.6    |   7
# 128.208.4.197   | 35.9.27.27      | 192.122.183.181 |   9
# 128.208.4.197   | 35.9.27.27      | 198.108.22.69   |  10
# 128.208.4.197   | 35.9.27.27      | 35.9.82.41      |  11



class RouterNames
	@@ip2router=Hash.new
	@@routercount=1
	def RouterNames.getName(ip,type='R')
		if ! @@ip2router[ip]
			@@ip2router[ip] = "#{type}#{@@routercount}"
			@@routercount+=1
		end
		@@ip2router[ip]
	end
	def RouterNames.each 
		@@ip2router.each { |k,v|
			yield k,v
		}
	end
end


lastsrc=lastdst=lastresp=""
lastttl="-1"
links = Hash.new

File.open(ARGV[0]).each { |line|
	#[ src, dst, resp, ttl] = line.split(/[\s\|]+/)
	arr = line.split(/[\s\|]+/)
	src=arr[1]
	dst=arr[2]
	resp=arr[4]
	ttl=arr[3]
	if src == lastsrc && dst == lastdst
		if ttl.to_i == lastttl.to_i + 1
			r1 = RouterNames.getName(lastresp)
			r2 = RouterNames.getName(resp)
			links["Link	#{r1}:#{lastresp} -- #{r2}:#{resp}	: TR"]=true
		# else do nothing
		end
	else	# new trace
		if ttl == '1'
				r1 = RouterNames.getName(src,"S")
				r2 = RouterNames.getName(resp)
				links["Link	#{r1}:#{src} -- #{r2}:#{resp}	: TR"]=true
		end
	end
	lastsrc=src
	lastdst=dst
	lastresp=resp
	lastttl=ttl
}
	
RouterNames.each { |ip,router|
	if router =~ /^R/
		puts "Router #{router} nAlly=1 #{ip}"
	elsif router =~ /^S/
		puts "Source #{router} nAlly=1 #{ip}"
	else
		raise "unknown router type #{router}"
	end
}

links.each_key { |k|
	puts k
}
