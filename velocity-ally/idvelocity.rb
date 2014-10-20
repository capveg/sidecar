#!/usr/bin/ruby
#!/usr/bin/srinterpreter
# -*- mode: Ruby -*-
# Run in unsafe / debug mode to get undns, which handles

require "progressbar"
require "progressbar_mixin"

class IDVelocityException < Exception
end
class IDVelocity
	IDMAX=65536
	MyEpoch=1209707959.56698
	Warn=true
	@@aliasThresh=100
	MaxSlopeErr=0.2
	MaxOffsetErr=0.2

  attr_reader :ip, :data, :needUpdate, :dataSorted, :timeSeries

	def initialize(ip)
		@ip=ip
		@data=Hash.new
		@dataSorted=nil
		@needUpdate=true
	end

	def warn(str)
		$stderr.puts "WARN:	" + str if Warn
	end

	def update(id,time)
		time-=MyEpoch	unless time < MyEpoch
		@data[time]=id
		@needUpdate=true
	end

	def guessIDatTime(t)
		if @needUpdate
			self.updateRate()
		end
		if ! @slope || ! @offset
			raise IDVelocityException.new("Brokenness for ip #{@ip} : no slope or offset")
		end
		# given the estimated rate and the last time
		# entry, figure out a guess of where the ID is
		# at time 't'
		raise IDVelocityException.new("Tried to guess a point for ip #{@ip} "+
					"but it has not enough data") if @data.length < 2
		# step 1: linear search for indexes on either side of t
		# FIXME : binary search would be better
		found=-1
		(1...@dataSorted.length).each{ |i|
			t1 = @dataSorted[i]
			t0 = @dataSorted[i-1]
			if t0<=t and t<=t1
				found=i
			end
		}
		# step 2: guess based on where we found t in our data
		if found!=-1
			# linearly interpolate between the two points in the @timeSeries
			t1 = @dataSorted[found]
			t0 = @dataSorted[found-1]
			percent = (t-t0)/(t1-t0)
			return (((@timeSeries[t1]-@timeSeries[t0])*percent) + @timeSeries[t0]) % IDMAX
		elsif (t < @dataSorted[0]) or (t > @dataSorted[@dataSorted.length-1])
			# asked for point before or after we have data, return slope*t+offset
			return (@slope*t+@offset)%IDMAX
		else
			id = @data[t]
			raise "Hell" unless id
			return id	# we should have that exact value
		end
	end

	## begin bender munging
	def interpolateIDFromPoints(before_t, before_id, after_t, after_id, desired_time)
	  if desired_time > after_t or desired_time < before_t
	    puts "#{before_t} < #{desired_time} < #{after_t}"
	    raise "Hell"
	  end
	  percent = (desired_time - before_t) / (after_t - before_t)
	  return ((after_id - before_id) * percent + before_id) % IDMAX
	end

	def veloDistance(velo)
	  # go through each sorted array of time, taking the lowest value
	  # from either array.

	  self.updateRate() if @needUpdate
	  velo.updateRate() if velo.needUpdate

	  our_index = 0
	  their_index = 0
	  sum = 0.0
	  points = 0

	  if @data.length < 2 or velo.data.length < 2
	    raise IDVelocityException.new("Tried to guess a point for ip #{@ip} "+
					  "but it has not enough data")
	  end

	  # in the beginning, one series will have points before the other series does
	  while (our_index < @dataSorted.size and @dataSorted[our_index] < velo.dataSorted[0])
	    # estimate value based on velo.slope
	    time = @dataSorted[our_index]
	    est_id = (velo.slope*time + velo.offset) % IDMAX

	    low, high = [est_id, @data[time]].sort
	    err = [high - low, 65536 + low - high].min

	    sum += err
	    points += 1
	    our_index += 1
	  end

	  while (their_index < velo.dataSorted.size and velo.dataSorted[their_index] < @dataSorted[0])
	    time = velo.dataSorted[their_index]
	    est_id = (@slope*time + @offset) % IDMAX

	    low, high = [est_id, velo.data[time]].sort
	    err = [high - low, 65536 + low - high].min

	    sum += err
	    points += 1
	    their_index += 1
	  end

	  # in the middle, points will be interspersed
	  # preconditions:
	  #       1) either their_index == 0 or our_index == 0
	  #      if their_index == 0, let beginning = theirs.  else beginning = ours.
	  #       2) other[other_index - 1] < beginning[0] < other[other_index]
	  while (our_index < @dataSorted.size and their_index < velo.dataSorted.size) do
	    first_ours = @dataSorted[our_index]
	    first_theirs = velo.dataSorted[their_index]

	    if first_theirs < first_ours
	      # estimate ID.theirs at time.ours
	      prev_ours = @dataSorted[our_index - 1]
	      est_id = interpolateIDFromPoints(prev_ours, @timeSeries[prev_ours],
					       first_ours, @timeSeries[first_ours],
					       first_theirs)
	      sum += (est_id - velo.data[first_theirs]).abs
	      points += 1
	      their_index += 1

	    elsif first_ours < first_theirs
	      # estimate ID.ours at time.theirs
	      prev_theirs = velo.dataSorted[their_index - 1]
	      est_id = interpolateIDFromPoints(prev_theirs, velo.timeSeries[prev_theirs],
					       first_theirs, velo.timeSeries[first_theirs],
					       first_ours)
	      sum += (est_id - @data[first_ours]).abs
	      points += 1
	      our_index += 1

	    else  # times are the same
	      # I think wrapping will screw us here, with neglible probability
	      sum += (@data[first_ours] - velo.data[first_theirs]).abs
	      points += 2
	      our_index += 1
	      their_index += 1
	    end
	  end

	  # in the end, one series will have points extending beyond the other series
	  while (our_index < @dataSorted.size)
	    # estimate value based on velo.slope
	    time = @dataSorted[our_index]
	    est_id = (velo.slope*time + velo.offset) % IDMAX
	    sum += (est_id - @data[time]).abs
	    points += 1
	    our_index += 1
	  end

	  while (their_index < velo.dataSorted.size)
	    time = velo.dataSorted[their_index]
	    est_id = (@slope*time + @offset) % IDMAX
	    sum += (est_id - velo.data[time]).abs
	    points += 1
	    their_index += 1
	  end

	  return sum / points
	end


	def veloDistanceIntersectionOnly(velo)
	  # go through each sorted array of time, taking the lowest value
	  # from either array.

	  self.updateRate() if @needUpdate
	  velo.updateRate() if velo.needUpdate

	  our_index = 0
	  their_index = 0
	  sum = 0.0
	  points = 0

	  if @data.length < 2 or velo.data.length < 2
	    raise IDVelocityException.new("Tried to guess a point for ip #{@ip} "+
					  "but it has not enough data")
	  end

	  # in the beginning, one series will have points before the other series does
	  while (@dataSorted[our_index] < velo.dataSorted[0])
	    our_index += 1
	  end

	  while (velo.dataSorted[their_index] < @dataSorted[0])
	    their_index += 1
	  end

	  # in the middle, points will be interspersed
	  # preconditions:
	  #       1) either their_index == 0 or our_index == 0
	  #      if their_index == 0, let beginning = theirs.  else beginning = ours.
	  #       2) other[other_index - 1] < beginning[0] < other[other_index]
	  while (our_index < @dataSorted.size and their_index < velo.dataSorted.size) do
	    first_ours = @dataSorted[our_index]
	    first_theirs = velo.dataSorted[their_index]

	    if first_theirs < first_ours
	      # estimate ID.theirs at time.ours
	      prev_ours = @dataSorted[our_index - 1]
	      est_id = interpolateIDFromPoints(prev_ours, @data[prev_ours],
					       first_ours, @data[first_ours],
					       first_theirs)
	      #	      puts "est: #{est_id}  actual: #{velo.data[first_theirs]}"

	      sum += (est_id - velo.data[first_theirs]).abs
	      points += 1
	      their_index += 1

	    elsif first_ours < first_theirs
	      # estimate ID.ours at time.theirs
	      prev_theirs = velo.dataSorted[their_index - 1]
	      est_id = interpolateIDFromPoints(prev_theirs, velo.data[prev_theirs],
					       first_theirs, velo.data[first_theirs],
					       first_ours)
	      #	      puts "est: #{est_id}  actual: #{@data[first_ours]}"

	      sum += (est_id - @data[first_ours]).abs
	      points += 1
	      our_index += 1

	    else  # times are the same
	      # I think wrapping will screw us here, with neglible probability
	      sum += (@data[first_ours] - velo.data[first_theirs]).abs
	      points += 2
	      our_index += 1
	      their_index += 1
	    end
	  end

	  if points == 0
	    raise IDVelocityException.new("no intersection with #{@ip} and #{velo.ip}")
	  end

	  return sum/points

	end

        ## end bender munging


	def old_veloDistance(velo)
		points=0.0
		sum=0.0

		# compare our points against them
		@data.each{ |time,id|
			v_id = velo.guessIDatTime(time)
			#sum += (id-v_id)*(id-v_id)
			sum += (id-v_id).abs
			points+=1
		}
		# compare their points against ours
		velo.data.each{ |v_time,v_id|
			id = self.guessIDatTime(v_time)
			#sum += (id-v_id)*(id-v_id)
			sum += (id-v_id).abs
			points+=1
		}
		raise IDVelocityException.new("veloDistance : #{@ip} #{velo.ip} :: no "+
					"points between either velocityid!!") unless points>0.0
		#return Math.sqrt(sum)/points
		return (sum)/points
	end

#	def ip
#		@ip
#	end


	def slope
		if @needUpdate
			self.updateRate()
		end
		@slope
	end
	def offset
		if @needUpdate
			self.updateRate()
		end
		@offset
	end

	def updateRate
		if @data.length < 2
			raise IDVelocityException.new("Tried to calculate ID rate for IP #{@ip} but"  +
					" has less than two estimates")
		end
		# step #1 ; store the sorted order of the time series for speed's sake
		@dataSorted=@data.keys.sort
		# step #2 ; compute a cheap estimate of the slope to estimate time to wrap
		estimates=0.0
		sum=0.0
		(1...@dataSorted.length).each { |i|	# note : "..." implies open end inferval [1,len)
			t1 = @dataSorted[i]
			t0 = @dataSorted[i-1]
			if @data[t1] > @data[t0]	# if the more recent entry is higher then the less recent
				sum += (@data[t1] - @data[t0])/(t1-t0)
				estimates+=1
			end
		}
		if estimates == 0 or sum ==0
			# our data is so screwy that we didn't get two monotonicly increasing points
			# just guess that the slope is 10 ; it's likely from the data that we've seen
			#  	(this is an extremely uncommon corner case)
			raise IDVelocityException.new("Data for #{@ip} insufficiently frequent to guess slope")
			guess_slope = 10.0
		else
			# average of estimates
			guess_slope = sum/estimates
		end
		time_to_wrap = IDMAX/guess_slope

		# step 3: now that we know how often we wrap, create @timeSeries that reflects what an
		#		infinite counter would look like
		@timeSeries=Hash.new
		@timeSeries[@dataSorted[0]]=@data[@dataSorted[0]]	# put the first datapoint into place
		nWraps=0
		tooFar=false
		(1...@dataSorted.length).each{ |i|
			t1 = @dataSorted[i]
			t0 = @dataSorted[i-1]
			id1 = @data[t1]
			id0 = @data[t0]
			ts0 = @timeSeries[t0]
			if (t1-t0) <= time_to_wrap	# did we have time to wrap?
				# only wrapped if id1< id0
				if id1 < id0
					nWraps+=1
				end
			else
				tooFar=true
				nWraps += ((t1-t0)/time_to_wrap).floor
			end
			@timeSeries[t1]= (nWraps*IDMAX) +id1
		}
		raise IDVelocityException.new("IP #{@ip} has datapoints too far apart; skipping to be conservative") if tooFar
		# step 4: now do a proper linear regression

		self.doLineFit
		@needUpdate=false
	end

	def datapoints
		@data.length
	end
	def lineFit
		if @needUpdate
			self.updateRate()	# this will also call doLineFit
		end
		return [@offset,@slope,@offset_stderr,@slope_stderr,@data.length]
	end

	def IDVelocity.unittest
		v = IDVelocity.new("1.2.3.4")
		(0..10).each { |i|
			v.update((i+65530)%IDVelocity::IDMAX,i)
		}
		guess = v.guessIDatTime(12)
		raise Exception.new("IDVelocity guessed badly: #{guess} != 6")  unless guess==6
		off,slope, off_err,slope_err, n= v.lineFit()
		puts "Off=#{off} +/- #{off_err}"
		puts "Slope=#{slope} +/- #{slope_err}"

		v2 = IDVelocity.new("1.2.3.4")	# from wikipedia example
		v2.update(2,-1)
		v2.update(3,0)
		v2.update(3,2)
		v2.update(4,4)
		off,slope, off_err,slope_err, n= v2.lineFit()
		puts "Off=#{off} +/- #{off_err}"
		puts "Slope=#{slope} +/- #{slope_err}"

		puts "distance(v1,v1) = #{v.veloDistance(v)}"
		puts "distance(v2,v2) = #{v2.veloDistance(v2)}"
		puts "distance(v1,v2) = #{v.veloDistance(v2)}"
		puts "distance(v2,v1) = #{v2.veloDistance(v)}"
	end
	def IDVelocity.resolve(datafile, pairsfiles)
		ips = Hash.new
		File.open(datafile).each_progress("Parsing Data") { |line|
			#12.118.116.70    12.118.116.70     1209709104.82477    6874                 Icmp
			(src,dst,time,id,id_rev,type) = line.strip.chomp.split
				if time != '-'       # if we got a valid response
					if !ips[src] # create entry if it doesn't exist
						ips[src]=IDVelocity.new(src)
					end
					if type =~ /Icmp_t=3_c=3/ or type =~ /Tcp/
						ips[src].update(id.to_i,time.to_f)
					else
						# ignore for now: FIXME should count or something
					end
				end
		}

	        pairsfiles.each do |pairsfile|
 		 linecount=0
	         out = File.open(pairsfile+".dump","w+")
		 File.open(pairsfile).each_progress("Testing aliases") { |line|
			linecount+=1
			if line =~ /(\d+\.\d+\.\d+\.\d+)\s+(\d+\.\d+\.\d+\.\d+)/
				ip1=$1
				ip2=$2
				if ! ips[ip1]
					$stderr.puts "No data for #{ip1}; skipping"
				elsif ! ips[ip2]
					$stderr.puts "No data for #{ip1}; skipping"
				else
					begin
						dist = ips[ip1].veloDistance(ips[ip2])
						#d2 = ips[ip1].veloDistanceIntersectionOnly(ips[ip2])

						if dist < IDVelocity.threshold
							res="ALIAS!"
						else
							res="NOT_ALIAS."
						end
						n1 = ips[ip1].datapoints
						n2 = ips[ip2].datapoints
						out.puts "#{ip1} #{ip2} :: #{res} velocity:	" +
							"d: %.2f a/b/n %.2f %.2f %d a/b %.2f %.2f %d" % [  dist,
								ips[ip1].slope, ips[ip1].offset,n1,
								ips[ip2].slope, ips[ip2].offset,n2]
					rescue IDVelocityException => e
						$stderr.puts e
					end
				end
			else
				$stderr.puts "UNparsed: #{pairsfile}:#{linecount} '#{line.chomp}'"
			end
		}
		out.close
	  end
	end

	def IDVelocity.threshold
		@@aliasThresh
	end
	protected
	def doLineFit
		# this should only be called from updateRate
		# http://en.wikipedia.org/wiki/Linear_least_squares#Example
		raise IDVelocityException.new("Too few data points (#{@data.length}) to curve fit -- need three") unless @data.length > 2
		#if @needUpdate	# depends on @timeSeries existing
		#	raise IDVelocityException.new("Don't call lineFit directly")
		#end
		sum_t=0.0
		sum_id=0.0
		sum_t2=0.0
		sum_t_id=0.0
		@dataSorted.each { |time|
			ts = @timeSeries[time]  # this is the id values converted to not wrap
			sum_t 	+= time
			sum_id	+= ts
			sum_t2 	+= time*time
			sum_t_id+= ts *time
		}
		n = @data.length
		d = n * sum_t2 - sum_t*sum_t
		@offset= (sum_t2*sum_id - sum_t*sum_t_id)/d
		@slope = (n * sum_t_id - sum_t*sum_id)/d

		@sum_squares=0
		@dataSorted.each { |time|
			id = @data[time]
			err = id - (@offset + time*@slope)%IDMAX	# residual error
			@sum_squares += err*err
		}

		begin
		@offset_stderr = Math.sqrt( (@sum_squares/(n-2)) * (sum_t2/d))
		@slope_stderr = Math.sqrt( (@sum_squares/(n-2)) * (n/d))
		raise IDVelocityException.new("IP #{@ip}: slope fit is too poor stddev/slope=#{@slope_stderr/@slope}") if (@slope_stderr/@slope) > IDVelocity.MaxSlopeErr
		raise IDVelocityException.new("IP #{@ip}: offset fit is too poor stddev/offset=#{@offset_stderr/@offset}") if (@offset_stderr/@offset) > IDVelocity.MaxOffsetErr
		rescue Exception => e
		rescue Exception => e
			$stderr.puts "Got Exception #{e} processing ip #{@ip} n=#{n} sum_squres=#{@sum_squares} sum_t2=#{sum_t2} d=#{d} sum_t=#{sum_t}"
			raise IDVelocityException.new("pathologically bad data for #{@ip}")
		end

	end
end

if $0 == __FILE__
	if ARGV[0] == '-test'
		IDVelocity.unittest
	elsif ARGV[0] =~ /^-resol/
		IDVelocity.resolve(ARGV[1],ARGV[2..-1])
	else
		$stderr.puts "Usage:\n #{$0} <-test|-resolve datafile pairsfile>"
	end


end
