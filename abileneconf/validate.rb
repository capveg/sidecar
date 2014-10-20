#!/usr/bin/ruby

#	# clean the unlinked and unalaised "routers" out of the observed graph
#	./validate.rb -clean observed-original.adj 
#	mv observed-original-cleaned.adj observed.adj
#	# remove leaf nodes that we have no router config (truth) info about
#	./validate.rb -defringe abilene.adj		
#	# compute the differences between truth and observed
#	./validate.rb -validate abilene-defringed.adj observed.adj > abilene-defringed-observed-out
#
#


# IpHash gives hash like symantics to a pair of ips h[ip1,ip2] = val
class IpHash 
	def initialize
		@data = Hash.new
	end
	def [](ip1,ip2=nil)
		if !  @data[ip1] || (ip2 && ! @data[ip1][ip2])
			nil
		elsif !ip2
			@data[ip1]
		else
			@data[ip1][ip2]
		end
	end
	def exists(ip1)
		@data[ip1]
	end
	def []=(ip1,ip2,val)
	 	@data[ip1] = Hash.new unless @data[ip1]
	 	@data[ip1][ip2] = Hash.new unless @data[ip1][ip2]
		@data[ip1][ip2]=val
	end
	def size
		count =0
		self.each { |ip1,ip2|
			count+=1 if ip1< ip2	# only count (a,b) not (a,a) or (b,a)
		}
		return count
	end
	def ips
		@data.keys.collect { |ip1 |
			[ ip1 ]  + @data[ip1].keys 
		}.flatten.uniq
	end
	def delete(ip1,ip2)
		@data[ip1].delete(ip2)
		@data.delete(ip1) if @data[ip1].size == 0
	end
	def each 
		@data.each_key { |ip1|
			@data[ip1].each_key { |ip2|
				yield ip1,ip2
			}
		}
	end
	def computeTransitiveClosure
		# adapted from CLR, page 563; they claim this is good even if it is O(n^3)
		@data.each_key { |k|
			@data[k].each_key { |i|
				@data[k].each_key { |j|
					self[i,j]=true 
				}
			}
		}
	end
	def IpHash.selfTest
		f = IpHash.new
		f["foo","foo"]=true
		f["foo","bar"]=true
		f.delete("foo","foo")
		f.delete("foo","bar")

		if f.exists("foo")
			raise "Broken" 
		else
			puts "IpHash passes selftest"
		end
	end
end

class Adjacency
	attr_writer :rrlinks, :trlinks, :aliases, :ip2router , :router2routerType
	attr_reader :rrlinks, :trlinks, :aliases, :ip2router , :router2routerType
	def initialize
		@rrlinks = IpHash.new 
		@trlinks = IpHash.new
		@aliases = IpHash.new
		@ip2router = Hash.new
		@router2routerType = Hash.new
	end
	def link(ip1,ip2)
		rrlinks[ip1,ip2] || trlinks[ip1,ip2]
	end
	def stats 
		"%d aliases 	%d rrLinks	%d trLinks" % [ aliases.size, rrlinks.size, trlinks.size]
	end
	def routers
		@router2routerType.keys
	end
	def ips
		@ip2router.keys
	end
	def Adjacency.parseAdj(graphfile,filter=nil,filterstr=nil)
		# filter is a hash where filter[ip]==true for IPs of interest
		routers = Hash.new
		rrlinks   = IpHash.new
		trlinks   = IpHash.new
		ip2router = Hash.new
		router2routerType = Hash.new
		File.open(graphfile,"r").each { |line|
			if(line =~ /^Link/)
				# 0    1      2            3     4    5             6
				#Link  S4_N:219.243.200.37 -- R3_B:219.243.200.38 : RR
				tokens=line.split(/[:\s]+/)
				# it's important to group all aliases together
				# 	then filter them pair wise to make sure
				# 	that sure that uninteresting, bad aliases get brought to light
				routers[tokens[1]] = Array.new unless routers[tokens[1]]
				routers[tokens[1]] << tokens[2] unless routers[tokens[1]].index(tokens[2])
				routers[tokens[4]] = Array.new unless routers[tokens[4]]
				routers[tokens[4]] << tokens[5] unless routers[tokens[4]].index(tokens[5])
				ip2router[tokens[2]]=tokens[1]
				ip2router[tokens[5]]=tokens[4]
				if (tokens[6] =~ /^(RR|STR)/)
					rrlinks[tokens[2],tokens[5]]=true
				elsif (tokens[6] =~ /^TR$/)
					trlinks[tokens[2],tokens[5]]=true
				# else ignore UNKNOWN links
				end
			elsif (line =~ /^(Router|Source|Endhost|NAT|Hidden)/)
				# "Router R2 nAlly=32 80.231.134.30 64.57.29.242 64.57.28.242 64.57.28.15 ..."
				tokens =line.chomp.split
				router2routerType[tokens[1]]=tokens[0]
				tokens[3..-1].each { |ip|
					routers[tokens[1]] = Array.new unless routers[tokens[1]]
					routers[tokens[1]] << ip unless routers[tokens[1]].index(ip) # add if not already there
					ip2router[ip]=tokens[1]
				}
			end
		}
		adj = Adjacency.new
		if(filter)
			nAliases=0
			nTrLinks=0
			nRrLinks=0
			routers.each { |router,iplist|
				found=false
				nAliases += iplist.size * (iplist.size - 1 )
				iplist.each{ |ip|
					found=true if filter[ip]
				}
				if(found)
					raise "Undef'd router " unless router2routerType[router]
					adj.router2routerType[router]=router2routerType[router]
					iplist.each{ |ip|
						# make all of the aliases link to the first one
						# we will compute the transitive set in a bit
						adj.aliases[ip,iplist[0]]=true	
						adj.aliases[iplist[0],ip]=true	
						adj.ip2router[ip]=ip2router[ip]
					}
				end
			}
			trlinks.each { |src,dst|
				nTrLinks += 1
				if filter[src] && filter[dst]	# if both ends of link is in the filter list
					adj.ip2router[src]=ip2router[src]
					adj.router2routerType[ip2router[src]]=router2routerType[ip2router[src]]
					adj.trlinks[src,dst]=true
					adj.ip2router[dst]=ip2router[dst]
					adj.router2routerType[ip2router[dst]]=router2routerType[ip2router[dst]]
				end
			}
			rrlinks.each { |src,dst|
				nRrLinks += 1
				if filter[src] && filter[dst]	# if both ends of link is in the filter list
					adj.ip2router[src]=ip2router[src]
					adj.router2routerType[ip2router[src]]=router2routerType[ip2router[src]]
					adj.rrlinks[src,dst]=true
					adj.ip2router[dst]=ip2router[dst]
					adj.router2routerType[ip2router[dst]]=router2routerType[ip2router[dst]]
				end
			}
			puts "ObservedGraph(prefilter): %d aliases     %d rrLinks      %d trLinks" % [ nAliases, nRrLinks, nTrLinks]
			filterName='-filtered'
			filterName += filterstr if filterstr
			filterName+='.adj'

			filtered=graphfile.sub(/\.adj/,filterName)
			puts "Outputting filtered graph to #{filtered}"
			adj.print(filtered)
		else	# we don't have a filter list specified
			adj.ip2router=ip2router	# just copy these over
			adj.router2routerType=router2routerType	# just copy these over
			routers.each { |router,iplist|	# just copy over all of the aliases
				iplist.each{ |ip|
					adj.aliases[ip,iplist[0]]=true
					adj.aliases[iplist[0],ip]=true	# create a chain of aliases and let the transitive aliases deal 
				}
			}
			adj.trlinks = trlinks # and all of the tr links
			adj.rrlinks = rrlinks # and all the rr links
		end
		adj
	end
	def clean!	# remove any router that is has no outgoing links  and has no aliases
		# temporarily remove trivial aliases
		@aliases.each { |ip1,ip2|
			@aliases.delete(ip1,ip2) if ip1 == ip2	# remove all trivial aliases
		}
		killList=Hash.new
		# foreach IP, flag it for deletion if it has no outgoing links  and has no aliases
		@ip2router.each_key { |ip1|
			if ! @aliases.exists(ip1) && ! @rrlinks.exists(ip1) &&  ! @trlinks.exists(ip1)
				killList[ip1]=true	# flag this IP/router for deletion
			end
		}
		# unflag IPs/routers that have incoming links
		[@rrlinks,@trlinks].each { |links| 
			links.each { |ip1,ip2|
				killList.delete(ip2)	if killList[ip2]
			}
		}
		# remove IPs from ip2router and @router2routerType lists if they are in the kill list
		$stderr.puts "Cleaning #{killList.size} ips from adjacency"
		killList.each_key{ |ip|
			@router2routerType.delete(@ip2router[ip])
			@ip2router.delete(ip)
		}
		# aliases, rrlinks, and trlinks lists should remain unchanged, by definition
		# DONE: add back trival aliases; somethings might depend on them
		[ @aliases, @rrlinks, @trlinks].each { |ipHash|
			ipHash.each { |ip1,ip2|
				@aliases[ip1,ip1]=true;
				@aliases[ip2,ip2]=true;
			}
		}
	end
	def defringe!
		@aliases.each { |ip1,ip2|
			@aliases.delete(ip1,ip2) if ip1 == ip2	# remove all trivial aliases
		}
		# remove all links where one router only had trivial aliases
		[@rrlinks,@trlinks].each { |links| 
			links.each { |ip1,ip2|
				links.delete(ip1,ip2) unless @aliases.exists(ip1) && 
						@aliases.exists(ip2)
			}
		}
		# clean up ip2router and router2routerTypeto only contain still existing ips
		@ip2router.each_key { |ip|
			if ! @aliases.exists(ip)
				@router2routerType.delete(@ip2router[ip])
				@ip2router.delete(ip)
			end
		}
		# add back trival aliases; somethings might depend on them
		[ @aliases, @rrlinks, @trlinks].each { |ipHash|
			ipHash.each { |ip1,ip2|
				@aliases[ip1,ip1]=true;
				@aliases[ip2,ip2]=true;
			}
		}
	end
	def print(outfile)
		routers = Hash.new
		[ @aliases, @rrlinks, @trlinks].each { |ipHash|
			ipHash.each { |ip1,ip2|
				router1 = @ip2router[ip1]
				raise "When creating #{outfile}; ip1 #{ip1} has no associated router (#{:ipHash.id2name})" unless router1
				router2 = @ip2router[ip2]
				raise "When creating #{outfile}; ip2 #{ip2} has no associated router (#{:ipHash.id2name})" unless router2
				routers[router1] = Hash.new unless routers[router1]
				routers[router1][ip1]=true
				routers[router2] = Hash.new unless routers[router2]
				routers[router2][ip2]=true
			}
		}
		File.open(outfile,"w+") { |out|
			routers.each_key { |router|
				out.puts "%s %s nAlly=%d %s" % [ @router2routerType[router],
							router,	 #	"ROUTER"
							routers[router].size, # "3"
							routers[router].keys.sort.join(' ')]	# "128.8.126.1 128.8.204.1"
							
			}
			@rrlinks.each { |ip1,ip2|
				out.puts "Link %s:%s -- %s:%s : RR" % [ @ip2router[ip1],ip1, @ip2router[ip2],ip2]
			}
			@trlinks.each { |ip1,ip2|
				out.puts "Link %s:%s -- %s:%s : TR" % [ @ip2router[ip1],ip1, @ip2router[ip2],ip2]
			}
		}
	end
end

######################################################
class ValidateAdjacency
	attr_reader :commonAliases, :observedOnlyAliases , :truthOnlyAliases , :confirmedWrongAliases, :verbose,
		:trLinks,:commonLinks, :observedOnlyLinks , :truthOnlyLinks , :confirmedWrongLinks , :altRRLinks
	attr_writer :verbose
	VerboseLevel=false
	def initialize(truthGraph, observedGraph,dontDefringe=false)
		@truthGraph=truthGraph
		if(truthGraph =~ /\.dlv$/)
			@truthGraph.sub(/\.dlv$/,'.adj')
			Kernel.system("dlv2adj.pl -o #{@truthGraph} #{truthGraph}")
		end
		@truthAdj=Adjacency.parseAdj(truthGraph)
		if ! dontDefringe && !(truthGraph =~ /-defringed.adj/)
			defringedOut = @truthGraph.sub(/\.adj$/,'-defringed.adj')
			puts "Defringing #{@truthGraph} to #{defringedOut}"
			@truthAdj.defringe!	
			@truthAdj.print(defringedOut)
		end
		@filter=ValidateAdjacency.calcFilter(@truthAdj)
		filterstr=truthGraph.gsub(/[-\.].*/,'')
		@observedAdj=Adjacency.parseAdj(observedGraph,@filter,'=' + filterstr)
		@verbose=VerboseLevel
	end

	def ValidateAdjacency.calcFilter(adj)
		adj.ip2router
	end
	def addRouterMap(truthRouter,observedRouter)
		@truth2observedMap = Hash.new	unless @truth2observedMap
		@observed2truthMap = Hash.new	unless @observed2truthMap
	
		@truth2observedMap[truthRouter] = Hash.new unless @truth2observedMap[truthRouter] 
		@observed2truthMap[observedRouter] = Hash.new unless @observed2truthMap[observedRouter]

		@truth2observedMap[truthRouter][observedRouter] = 
			@observed2truthMap[observedRouter][truthRouter]=true
	end
	def validateAliases
		@commonAliases= @observedOnlyAliases = @truthOnlyAliases = @confirmedWrongAliases = 0
		@missedJoinsCount=@badJoinsCount=0
		@observedAdj.aliases.each { |ip1,ip2|
			if ip1 < ip2	# stop double counting things
				if @truthAdj.aliases[ip1,ip2]
					@commonAliases+=1
					puts "CommonAlias: #{ip1} #{ip2} " if @verbose
					addRouterMap(@truthAdj.ip2router[ip1],@observedAdj.ip2router[ip1])
				else
					@observedOnlyAliases+=1
					if @truthAdj.ip2router[ip1] && @truthAdj.ip2router[ip2] && 
							@truthAdj.ip2router[ip1] != @truthAdj.ip2router[ip2]
						# if these two ips exist in the truth graph and are not on the same router
						@confirmedWrongAliases+=1
						puts "WrongAlias: #{ip1} #{ip2} (%s != %s) (%s and %s in observed)" % [ @truthAdj.ip2router[ip1],
									@truthAdj.ip2router[ip2],
									@observedAdj.ip2router[ip1],
									@observedAdj.ip2router[ip2]]
						addRouterMap(@truthAdj.ip2router[ip1],@observedAdj.ip2router[ip1])
						addRouterMap(@truthAdj.ip2router[ip2],@observedAdj.ip2router[ip1])
					else
						puts "ObservedOnlyAlias: #{ip1} #{ip2} (%s and %s in observed)" % [
						     @observedAdj.ip2router[ip1],
						     @observedAdj.ip2router[ip2]]
					end
				end
			# else ip1>= ip2; ignore
			end
		}
		@truthAdj.aliases.each { |ip1,ip2|
			if ip1 < ip2
				if ! @observedAdj.aliases[ip1,ip2]
					@truthOnlyAliases+=1
					puts "MissingAlias: #{ip1} #{ip2} " if @verbose
					# if both of these ips exist in the other mapping
					if @observedAdj.ip2router[ip1] and @observedAdj.ip2router[ip2]
						# add the mappings
						addRouterMap(@truthAdj.ip2router[ip1],@observedAdj.ip2router[ip1])
						addRouterMap(@truthAdj.ip2router[ip1],@observedAdj.ip2router[ip2])
					end
				end
			end
		}
	end
	def validateLinks
		@altRRLinks=@trLinks=@commonLinks= @observedOnlyLinks = @truthOnlyLinks = @confirmedWrongLinks = 0
		# foreach observed RR link ; see if there is a corresponding RR link in the truth
		@observedAdj.rrlinks.each { |ip1,ip2|
			if @truthAdj.rrlinks[ip1,ip2]
				@commonLinks +=1
				puts "CommonLink: #{ip1} #{ip2} " if @verbose
			else
				@observedOnlyLinks+=1
				if @truthAdj.ip2router[ip1] && @truthAdj.ip2router[ip2] && 
						@truthAdj.ip2router[ip1] == @truthAdj.ip2router[ip2]
					# if these two ips exist in the truth graph says they are on the same router
					@confirmedWrongLinks+=1
					puts "WrongLink: #{ip1} #{ip2} (%s == %s)" % [ @truthAdj.ip2router[ip1], @truthAdj.ip2router[ip2]]
				end
				
			end
		}
		# foreach observed TR link; make sure that it's not a bad link
		@observedAdj.trlinks.each { |ip1,ip2|
			foundTRlink=false	# we have to make sure there is not a tr link that follows this
			@truthAdj.aliases[ip1].each_key { |ip3|	# foreach alias with ip1
				# test to see if a tr link exists between the two routers
				foundTRlink=true if @observedAdj.trlinks[ip3,ip2]
			}
			if !foundTRlink == true
				@observedOnlyLinks+=1
				puts "ExtraLink: #{ip1} #{ip2} (%s == %s)" % [ @truthAdj.ip2router[ip1], @truthAdj.ip2router[ip2]]
			end
		}

		@truthAdj.rrlinks.each { |ip1,ip2|
			if ! @observedAdj.rrlinks[ip1,ip2]
				foundTRlink=false	# we have to make sure there is not a tr link that follows this
				foundAltRRlink=false	# we have to make sure there is not a tr link that follows this
				@truthAdj.aliases[ip1].each_key { |ip3|	# foreach alias with ip1
					# test to see if a tr link exists between the two routers
					foundTRlink=true if @observedAdj.trlinks[ip3,ip2]
					foundAltRRlink=true if @observedAdj.rrlinks[ip3,ip2]
				}
				if foundAltRRlink
					@altRRLinks+=1
					puts "altRRLink: #{ip1} #{ip2} " if @verbose
				elsif foundTRlink
					@trLinks+=1
					puts "trLink: #{ip1} #{ip2} " if @verbose
				else
					@truthOnlyLinks+=1
					puts "MissingLink: #{ip1} #{ip2} " if @verbose
				end
			end
		}
	end
	def stats(outfile)
		outfile.puts "ObservedGraph: " + @observedAdj.stats
		outfile.puts "TruthGraph: " + @truthAdj.stats 
	end
	def computeTransitiveClosure
		@truthAdj.aliases.computeTransitiveClosure
		@observedAdj.aliases.computeTransitiveClosure
	end

	def computerClusterSimilarity
		count=0
		score=0
		@observedAdj.ips.each { |ip1|
			@observedAdj.ips.each { |ip2|
				if ip1 < ip2		# ignore (ip1,ip1) and (ip2,ip1)
					next unless @truthAdj.ip2router[ip1] && @truthAdj.ip2router[ip2]
					count+=1
					if @truthAdj.ip2router[ip1]== @truthAdj.ip2router[ip2]
						# these ips are on the same router in reality; give +1 if we got it right
						raise "Undef'd ip1 #{ip1}" unless @observedAdj.ip2router[ip1]
						raise "Undef'd ip2 #{ip2}" unless @observedAdj.ip2router[ip2]
						score +=1 if @observedAdj.ip2router[ip1]== @observedAdj.ip2router[ip2]
					else	
						# these ips are on different routers in reality; give +1 if we got it right
						raise "Undef'd ip1 #{ip1}" unless @observedAdj.ip2router[ip1]
						raise "Undef'd ip2 #{ip2}" unless @observedAdj.ip2router[ip2]
						score +=1 if @observedAdj.ip2router[ip1]!=@observedAdj.ip2router[ip2]
					end
				end
			}
		}
		print "CLUSTERSCORE	%f 	score %d 	count %d" % [ score.to_f/count,score, count]
	end
	def dumpRouterMappings
		puts "Mappings from truth router labels to observed router labels (extra entries means superfluous):"
		superfluous=0
		split=0
		bad=0
		good=0
		missed=0
#		@truth2observedMap.each{ |trouter, orouters|
#			if orouters.keys.size==1 	# did we observe more then one router for a single real router?
#				if @observed2truthMap[orouters.keys[0]].keys.size ==1 
#					# one-to-one mapping == got it right		
#					right+=1
#				else
#					# will get tagged as a bad router, below
#				end
#			else
#				# this real router got split up
#				split+=1
#				# count the number of extra routers
#				superfluous+=orouters.size-1		
#			end
#			puts "#{trouter} #{orouters.size}: " + orouters.keys.join(" ")
#		}
#		puts "Mappings from observed router labels to truth router labels (extra entries mean mistakes):"
#		@observed2truthMap.each{ |orouter, trouters|
#			bad+=trouters.size-1		# there should be at most one entry here; anything more is bad
#			puts "#{orouter} #{trouters.size}: " + trouters.keys.join(" ")
#		}
		@truthAdj.routers.each{ |router|	# foreach router that we know exists
			if @truth2observedMap[router]	# if we have observed this router
				if @truth2observedMap[router].keys.size == 1	# if we observed this router as a single router
					if @observed2truthMap[@truth2observedMap[router].keys[0]].keys.size == 1 # and the observed data doesn't badly merge mutltiple real routers together
						good+=1
					else
						bad+=1		# this router was badly glommed onto something else
					end
				else
					split+=1	# this router was (incorectly) split up
					superfluous+= @truth2observedMap[router].keys.size-1	# count extra splits
				end
			else
				missed+=1
			end
		}
		actual = @truth2observedMap.keys.size
		puts "MAPPINGS: actual %d	missed %d	good %d		superfluous %d		split %d	bad %d" % 
			[ @truthAdj.router2routerType.size, @truthAdj.router2routerType.size-actual, 
				good, superfluous, split, bad]
		puts "ROUTERSINFERRED: truth %d observed %d " % [ @truthAdj.router2routerType.size, 
			@observedAdj.router2routerType.size]
	end
end

if $0 == __FILE__
	#f = Adjacency.new
	#f.rrlinks['1.1.1.1','2.2.2.2']=true
	#raise "bad" unless f.rrlinks["1.1.1.1",'2.2.2.2']
	if ARGV[0] == '-validate'
		va = ValidateAdjacency.new(ARGV[1],ARGV[2],ARGV[3])
		va.stats($stdout)
		puts "----- Pre-transitive aliases clossure"
		va.validateAliases
		va.computeTransitiveClosure
		puts "----- Post-transitive aliases clossure"
		va.validateAliases
		$stdout.puts "ALIAS-STATS commonAliases %d ; wrongAliases %d ; extraAliases %d ; missedAliases %d" % [ va.commonAliases,
										va.confirmedWrongAliases,
										va.observedOnlyAliases,
										va.truthOnlyAliases]
		va.validateLinks
		$stdout.puts "LINK-STATS commonLinks %d ; wrongLinks %d ; extraLinks %d ; missedLinks %d ; trLinks %d ; altRRLinks %d" % [ va.commonLinks,
										va.confirmedWrongLinks,
										va.observedOnlyLinks,
										va.truthOnlyLinks,
										va.trLinks,
										va.altRRLinks]
		va.dumpRouterMappings
		va.computerClusterSimilarity
	elsif ARGV[0] == '-test'
		puts "Parsing #{ARGV[1]}"
		adj = Adjacency.parseAdj(ARGV[1])
		outfile = ARGV[1].sub(/\.adj/,'-test.adj')
		puts "Printing test to #{outfile}"
		adj.print(outfile)
	elsif ARGV[0] == '-clean'
		puts "Parsing #{ARGV[1]}"
		adj = Adjacency.parseAdj(ARGV[1])
		puts "Cleaning #{ARGV[1]} (removing Routers that have no links or aliases)"
		adj.clean!
		outfile = ARGV[1].sub(/\.adj/,'-cleaned.adj')
		puts "Printing cleaned to #{outfile}"
		adj.print(outfile)
	elsif ARGV[0] == '-defringe'
		puts "Parsing #{ARGV[1]}"
		adj = Adjacency.parseAdj(ARGV[1])
		puts "Defringing #{ARGV[1]}"
		adj.defringe!
		outfile = ARGV[1].sub(/\.adj/,'-defringed.adj')
		puts "Printing defringed to #{outfile}"
		adj.print(outfile)
	else
		$stderr.puts "Usage::\n#{$0} [options] "
		$stderr.puts "		-validate <truth.adj|truth.dlv> observed.adj"
		$stderr.puts "		-test foo.adj		# creates foo-test.adj for debug"
		$stderr.puts "		-defringe foo.adj	# removes edge routers without aliases, i.e., fringe"
	end
end
