#!/usr/bin/ruby

###############################################
# Use Condor to adaptiveDlv solve stuff
#	store intermediate files for resolving w.x.y.z and a.b.c.d
#	into w/x/a/b/data-w.x.y.z-a.b.c.d.dlv and w/x/a/b/data-w.x.y.z-a.b.c.d.model
#

$sidecarDir=ENV['SIDECARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"

if ! Kernel.test(?d,$sidecarDir+ "/scripts")
	Kernel.system("echo No sidecar dir #{$sidecarDir}  on `hostname`| mail -s CONDOR_SUX capveg@cs.umd.edu" )
	raise "No sidecar dir #{$sidecarDir}  on " + `hostname`
end


$: << "#{$sidecarDir}/random_prober"
$: << "#{$sidecarDir}/scripts"
$: << "#{$sidecarDir}/scripts/ruby"
$: << $libDir
$: << '/usr/local/lib/ruby/1.8' # really should be there by default, but isn't

#begin
#        require 'dbi'   # install from http://rubyforge.org/projects/ruby-dbi/; see notes at bottom of
#			# scripts/genAll2Cliques.rb
#	rescue LoadError => e
#	        $stderr.puts "Need to install ruby-dbi from http://rubyforge.org/projects/ruby-dbi"
#		$stderr.puts " Read the bottom of the source of ips2ttldistance2db.rb for more info"
#		exit!
#end

begin 
$noScriptroute=true
require 'nspring-utils'
require 'fprogressbar'
require 'progressbar_mixin'
#require 'ips2ttldistance2db.rb'
#require 'adaptiveDlv'
	rescue LoadError => e
	        $stderr.puts e
		$stderr.puts "Include path " + $:.join(',')
		$stderr.puts "sideracr dir is #{$sidecarDir}"
		$stderr.puts "hostname == " +`hostname`
		ENV.each { |k,v|
			$stderr.puts "Env #{k} = #{v}"
		}
		exit!
end

class Dir
	def Dir.mkSuperDir(dir)	# mkdir -p, but doesnt fail if dir exists
		parts = dir.split(/\//)
		base = parts[0]==''  ?  "/#{parts.shift}" : '' 
		attempt=0
		while parts.length > 0
			base+= parts.shift
			begin
				Dir.mkdir(base) unless Kernel::test(?d,base)
			rescue SystemCallError => err
				# might be a race condition in mkdir'ing this directory
				# 	when lots of things run in parallel
				if SystemCallError.errno == Errno::EEXIST && attemp<2
					attempt+=1
					retry
				else
					raise(err)
				end
			end
			base += '/'
		end
	end
end

class File
	def File.test_and_size(f)
		if Kernel.test(?f,f)
			File.size(f)
		else
			-1
		end
	end
end

class PsqlHack
	PasswdFile="#{$sidecarDir}/scripts/pgpass"
	LocalPgpass="#{ENV['HOME']}/.pgpass"
	def PsqlHack.select(str)
		hostname = `hostname -f`.chomp 
		if hostname =~ /\.cs\.umd\.edu/
			server='drive.cs.umd.edu'
		else
			server='drive127.cs.umd.edu'
		end
		if(!Kernel::test(?e,LocalPgpass))
			`cp #{PasswdFile} #{LocalPgpass}`
			File.chmod(0600,LocalPgpass)
		end
		ENV['HOME']=ENV['CWD'] unless ENV['HOME']
		ENV['PGPASSFILE']="#{ENV['HOME']}/.pgpass"
		cmd = "psql -q -h #{server} -t -U capveg -c '#{str}'"
		$stderr.puts "Running '#{cmd}'"
		if block_given?
			IO.popen(cmd).collect{ |line|
				line.strip
				yield line
			}
			File.unlink(LocalPgpass)
		else
			arr= IO.popen(cmd).collect{ |line|
				line.strip
			}
			while arr[arr.length-1] =~ /^\s*$/	# remove any elements that are just white space at end
				arr.pop
			end
			File.unlink(LocalPgpass)
			return arr
		end
	end
	alias :select_all :select
end

class File
	include ProgressBar_Mixin
end

class CondorSolve
	Data2dlvCmd="#{$sidecarDir}/scripts/data2dlv.pl"
	TestfactsCmd="#{$sidecarDir}/scripts/adaptiveDlv.rb -f"
	Basedir='/fs/sidecar/run/alltrace'
	PSQL='psql'
	DefaultNJobs=300
	ResolveBase='resolved'
	ResolvePotentialBase='resolvedPotential'
	NumRepresentatives=1
	CondorBatchSize=1000
	Logdir='/tmp/capveg/logdir'
	SubmitAttempts=5
	MinModelSize=42 # "Best model: {}\n" + "Cost ([Weight:Level]): <0>\n"
	DlvMinSize=5000 # any dlv file under this size should be recomputed, b/c it's probably just comments
			# if this guesses badly, it is just inefficient, not incorrect
	

###########################################################################
	def initialize(table='traces')
		@table=table
		raise "#{Basedir} does not exists " unless Kernel::test(?d,Basedir)
		#ip2db=Ips2TTLdistance2db.new
		## create a database handle with constants stored in Ips2TTLdistance2db
		#@dbh=DBI.connect("DBI:Pg:dbname=#{ip2db.databasename};host=#{ip2db.databasehost}", 
		#		ip2db.databaseuser, ip2db.databasepasswd)
	end
###########################################################################
	def grabSrcIps
		$stderr.puts "Making list of all Src Ips in #{@table}"
		@allSrcIps= PsqlHack.select("SELECT src from #{@table}_src") 
		#@allSrcIps= PsqlHack.select("SELECT src from #{@table}_src limit 100") 
#		@allSrcIps= [  '12.46.129.15', 
#				'12.46.129.16',
#				'12.46.129.21', 
#				'12.46.129.23', 
#				'12.108.127.136', 
#				'12.108.127.138', 
#				'35.9.27.26', 
#				'35.9.27.27', 
#				'63.64.153.83', 
#				'63.64.153.84' ]
		$stderr.puts "#{@allSrcIps.length} Src Ips found in  #{@table}"
	end
###########################################################################
	def grabDstIps
		$stderr.puts "Making list of all Dst Ips in #{@table}"
		@allDstIps= PsqlHack.select("SELECT dst from #{@table}_dst ") 
		$stderr.puts "#{@allDstIps.length} Dst Ips found in  #{@table}"
	end
###########################################################################
	def srcdstAll(debug=nil,batchSize=nil,maxJobs=nil)
		maxJobs=DefaultNJobs unless maxJobs	# b/c we might have been called with nil
		dir="data"
		#batchSize=[1,[CondorBatchSize,queue.size/(2*maxJobs)].min].max unless batchSize
		batchSize=CondorBatchSize unless batchSize
		self.grabSrcIps
		self.grabDstIps
		if debug
			$stderr.puts "Running in debugging mode with only 1 dst/src pair"
			dstlist= @allDstIps[0..0]
		else
			dstlist= @allDstIps
		end
		$stderr.puts "Using batches of size #{batchSize}"
		totalcount=(@allSrcIps.size/2).ceil * dstlist.size	# nSrc/2 * nDst 
		queue=SizedQueue.new(maxJobs*3)
		$stderr.puts "Found #{totalcount} jobs to spawn"
		pb = ProgressBar.new("input", totalcount)
		$stderr.puts "Spawning #{maxJobs} consumer threads"
		consumers = (1..maxJobs).collect { |i|
			t = Thread.new {
				Thread.current['index']=i
				while (nextTask = queue.shift) != nil  
					condor_spawn_and_wait(nextTask)
					pb.inc(nextTask.split().size - 3)	# -srcdst src1 src2 dst1 [dst2 [..]]
				end
			}
		}
		Dir.mkSuperDir("#{Basedir}/#{dir}")
		logfilename="condorSolve.srcdst.log." + Time.now.to_s.gsub(/\s+/,'_')
		logfile = File.open(logfilename,"w+")
		$stderr.puts "Redirecting stdout to #{logfilename}"
		$stdout.reopen(logfile)
		start=Time.now
		$stderr.puts "Start time: #{start} "

		@allSrcIps.each_index { |i|
			next if (( i%2)==1)		# skip every other index to avoid double solving everything
							# double solving was originally done intentionally to force overlap to
							# detect conflicts, but is being removed for efficiency
			src1=@allSrcIps[i]
			src2=@allSrcIps[(i+1)%@allSrcIps.size ]	# when i == @allSrcIps.size, this is weird, but still valid
			count=0
			str="-srcdst #{src1} #{src2} "
			dstlist.each { |dst|
				str += dst + " "
				count+=1
				if count>= batchSize	# batch up dst ips until batchSize
					queue.push(str)	# push them on queue for waiting thread(s)
					count=0
					str="-srcdst #{src1} #{src2} "
				end
			}
			queue.push(str) if count > 0	# grab the last one
		}
		$stderr.puts "Done queuing"
		consumers.map { |t| queue.push(nil) }	# tell all threads there is nothing left to do
		consumers.map { |t| t.join }		# wait for all threads to finish
		finish=Time.now
		$stderr.puts "Finish time: #{finish}"
		$stderr.puts "Ellapsed seconds : #{(finish-start).to_f}; gathering hints"
	end
###########################################################################
	def fixAll(hints,batchSize=nil,maxJobs=nil)
		maxJobs=DefaultNJobs unless maxJobs	# b/c we might have been called with nil
		queue = Array.new
		dir="data"
		file= hints.sub(/\.hints-.+/,'.conflict-debug')
		$stderr.puts "Parsing #{file} for models to fix"
		File.open(file,"r").each { |line|
			#link(ip213_248_64_251,ip213_248_100_238,1) 2 alias(ip213_248_64_251,ip213_248_100_238) 2 (./12/46/128/232/clique-12.46.129.15-128.232.103.201.model;./12/46/129/12/clique-12.46.129.23-129.12.3.75.model) (./12/46/128/232/clique-12.46.129.15-128.232.103.201.model;./12/46/129/12/clique-12.46.129.23-129.12.3.75.model)
			tokens=line.split
			ips=tokens[0].split(/[(,)]/) 
			linkBelievers = tokens[4].split(/[();]/)
			aliasBelievers = tokens[5].split(/[();]/)
			ip1 = ips[1].sub(/^ip/,'').gsub(/_/,'.')
			ip2 = ips[2].sub(/^ip/,'').gsub(/_/,'.')
			(linkBelievers + aliasBelievers).each { |model|
				if model =~ /\S+/
					queue << Basedir + "/" + model
				end
			}
		}
		batchSize=[1,[CondorBatchSize,queue.size/(2*maxJobs)].min].max unless batchSize
		$stderr.puts "Using batches of size #{batchSize}"
		newqueue = Array.new
		count=0
		str="-fix #{hints} "
		queue.uniq.each {	|model|
			str+=model + " "
			count+=1
			if(count>=batchSize)
				newqueue << str
				str="-fix #{hints} "
				count=0
			end
		}
		queue=newqueue
		$stderr.puts "Found #{queue.length} conflicts to fix"
		Dir.mkSuperDir("#{Basedir}/#{dir}")
		logfilename="condorSolve.fixed.log." + Time.now.to_s.gsub(/\s+/,'_')
		logfile = File.open(logfilename,"w+")
		$stderr.puts "Redirecting stdout to #{logfilename}"
		$stdout.reopen(logfile)
		start=Time.now
		$stderr.puts "Start time: #{start} "
		queue.each_inparallel_progress(maxJobs,"Conflicts",true){ |str|
			condor_spawn_and_wait(str)
		}
		finish=Time.now
		$stderr.puts "Finish time: #{finish}"
		$stderr.puts "Ellapsed seconds : #{(finish-start).to_f}; gathering hints"
	end
###########################################################################
	def resolveAllConflicts(resolveType,command,file,maxJobs=nil)
		maxJobs=DefaultNJobs unless maxJobs	# b/c we might have been called with nil
		if (command == '-resolveAll')
			dir = ResolveBase
		elsif (command == '-resolveAllPotential')
			dir = ResolvePotentialBase
		else
			raise "Unknown resolve command #{command}"
		end
		queue = File.open(file,"r").collect { |line|
			#link(ip213_248_64_251,ip213_248_100_238,1) 2 alias(ip213_248_64_251,ip213_248_100_238) 2 (./12/46/128/232/clique-12.46.129.15-128.232.103.201.model;./12/46/129/12/clique-12.46.129.23-129.12.3.75.model) (./12/46/128/232/clique-12.46.129.15-128.232.103.201.model;./12/46/129/12/clique-12.46.129.23-129.12.3.75.model)
			tokens=line.split
			ips=tokens[0].split(/[(,)]/) 
			linkBelievers = tokens[4].split(/[();]/)[1..NumRepresentatives]	# pick the first two items; \( is zero index
			aliasBelievers = tokens[5].split(/[();]/)[1..NumRepresentatives]
			ip1 = ips[1].sub(/^ip/,'').gsub(/_/,'.')
			ip2 = ips[2].sub(/^ip/,'').gsub(/_/,'.')
			"#{resolveType} #{ip1} #{ip2} #{linkBelievers.join(' ')} #{aliasBelievers.join(' ')}"
		}
		$stderr.puts "Found #{queue.length} conflicts to solve"
		Dir.mkSuperDir("#{Basedir}/#{dir}")
		logfilename="condorSolve#{resolveType}.log." + Time.now.to_s.gsub(/\s+/,'_')
		logfile = File.open(logfilename,"w+")
		$stderr.puts "Redirecting stdout to #{logfilename}"
		$stdout.reopen(logfile)
		start=Time.now
		$stderr.puts "Start time: #{start} "
		batchsize = [queue.size/(2*DefaultNJobs),1].max
		$stderr.puts "Batching #{queue.size} jobs into batches of size #{batchsize}"
		queue = CondorSolve.batch(queue,batchsize)
		$stderr.puts "Total: #{queue.size} batched jobs"
		queue.each_inparallel_progress(maxJobs,"Conflicts",true){ |str|
			condor_spawn_and_wait(str)
		}
		finish=Time.now
		$stderr.puts "Finish time: #{finish}"
		$stderr.puts "Ellapsed seconds : #{(finish-start).to_f}; gathering hints"
		hints=file.sub(/conflict-debug/,"hints#{resolveType}")
		Kernel.system("find #{Basedir}/#{dir} -name \\*.hints | " +
			"xargs cat |sort > #{hints}")
		printHintsStats(hints)
	end
###########################################################################
	def printHintsStats(hints)
		aliases= links= timeout= unresolved= linecount=0
		File.open(hints,"r").each{ |line|
			linecount+=1
			case line
			when /^alias/
				aliases+=1
			when /^link/
				links+=1
			when /multiple models/
				unresolved+=1
			when /no valid models/
				timeout+=1
			end
		}
		$stderr.puts "STATS: #{links} links; #{aliases} aliases; #{timeout} timeout; " +
				"#{unresolved} unresolved; #{linecount} total"
	end
###########################################################################
	def all_cliques(maxJobs)
		grabSrcIps unless @allSrcIps
		maxJobs=DefaultNJobs unless maxJobs	# b/c we might have been called with nil
		$stderr.puts "Queueing #{@allSrcIps.length*@allSrcIps.length} possible pairs to solve"
		queue= @allSrcIps.map { |ip1|
			@allSrcIps.map { |ip2|
				if ip1.to_s < ip2.to_s
					"-clique #{ip1.to_s} #{ip2.to_s}"
				end
			}
		}.flatten.compact	# <--- magic
		logfilename="condorSolve-allCliques.log." + Time.now.to_s.gsub(/\s+/,'_')
		logfile = File.open(logfilename,"w+")
		$stderr.puts "Redirecting stdout to #{logfilename}"
		$stdout.reopen(logfile)
		batchsize = [queue.size/(2*DefaultNJobs),1].max
		$stderr.puts "Batching #{queue.size} jobs into batches of size #{batchsize}"
		queue = CondorSolve.batch(queue,batchsize)
		$stderr.puts "Total: #{queue.size} batched jobs"
		$stderr.puts "Start time: #{Time.now} "
		queue.each_inparallel_progress(maxJobs,"Cliques",true){ |str|
			condor_spawn_and_wait(str)
		}
		$stderr.puts "Finish time: #{Time.now}"
	end
###########################################################################
	def CondorSolve.str2outdir(str)
                # "-clique 1.2.3.4 5.6.7.8" --> "Basedir/1/2/5/6"
		tokens=str.split
		if tokens[0] == '-fix'	# hack
				# -fix /fs/sidecar/path/to/broken.model
				return File.dirname(tokens[2])
		elsif tokens[0] == '-batch'	# hack
				# -batch -job1 -job2
				tokens=str.split	# use first job as the representative outdir for this batch
				CondorSolve.str2outdir(CondorSolve.unbatch(tokens[1]).join(' '))
		else
			raise "Bad Args '#{str}'" unless tokens and tokens[1] and tokens[2]
			ip1 = tokens[1].split(/\./)
			raise "Bad Args '#{str}'" unless ip1 and ip1[0] and ip1[1]
			ip2 = tokens[2].split(/\./)
			raise "Bad Args '#{str}'" unless ip2 and ip2[0] and ip2[1]
			if tokens[0] == '-resolve'
				return "#{Basedir}/#{ResolveBase}/#{ip1[0]}/#{ip1[1]}/#{ip2[0]}/#{ip2[1]}"
			elsif  tokens[0] == '-resolvePotential'
				return "#{Basedir}/#{ResolvePotentialBase}/#{ip1[0]}/#{ip1[1]}/#{ip2[0]}/#{ip2[1]}"
			else
				return "#{Basedir}/data/#{ip1[0]}/#{ip1[1]}/#{ip2[0]}/#{ip2[1]}"
			end
		end
	end
###########################################################################
	def CondorSolve.str2base(str)
		# "-clique 1.2.3.4 5.6.7.8" --> "clique-1.2.3.4-5.6.7.8"
		# "-resolve 1.2.3.4 5.6.7.8 file1 file2 [..]" --> "resolve-1.2.3.4-5.6.7.8"
		if str =~ /^-fix/
			tokens=str.split
			File.basename(tokens[2]).sub(/clique-/,'fix-').sub(/\.model$/,'')
		elsif str =~ /-batch/
			tokens=str.split	# use first job as the representative outdir for this batch
			CondorSolve.str2base(CondorSolve.unbatch(tokens[1]).join(' '))
		elsif str =~ /-srcdst/
			tokens=str.gsub(/-/,'').split
			tokens[0..3].join('-')
		else
			tokens=str.gsub(/-/,'').split
			tokens[0..2].join('-')
		end
	end
###########################################################################
	def CondorSolve.str2subbase(str)
		# "-srcdst 1.2.3.4 5.6.7.8 2.3.4.5" --> "2/3/srcdst-1.2.3.4-5.6.7.8-2.3.4.5"
		raise unless str =~ /^-srcdst/
		tokens=str.gsub(/-/,'').split
		octet=tokens[3].split(/\./)
		return octet[0] + '/' + octet[1] + '/' + tokens[0..2].join('-')
	end
###########################################################################
	def condor_spawn_and_wait(str)
		outdir = CondorSolve.str2outdir(str)
		base = CondorSolve.str2base(str)
		Dir.mkSuperDir(outdir) unless Kernel::test(?d, outdir)
		Dir.mkSuperDir(Logdir) unless Kernel::test(?d, Logdir)
		commandone = "condor_submit "+
					"-a OutputDir='#{outdir}' " + 
					"-a InputString='#{str}' "+
					"-a Base='#{base}' " +
					" /fs/sidecar/condor/condorSolve-template.cmd 2>&1 " 
		commandtwo = "condor_wait %s/%s.log 2>&1 " % [ Logdir,base]
		if str =~ /-srcdst/
			subbase = CondorSolve.str2subbase(str)
			model = "#{outdir}/#{subbase}.model"
		else
			model = "#{outdir}/#{base}.model"
		end
		if(!Kernel::test(?f,model))
			attempts=SubmitAttempts
			success=false
			while !success && attempts>0
				success= Kernel::system(commandone)
				attempts-=1
				puts "Resubmitting job " + str.split()[0..3].join(' ') unless success
			end
			if success
				Kernel::system(commandtwo)
			else
				$stderr.print "Really, Really giving up on #{base}; failed after #{SubmitAttempts} attempts"
			end
		else
			$stderr.puts "SKIPPING: already done  #{outdir}/#{base} :: #{str.slice(0,[20,str.length].min)}"
		end
	end
###########################################################################
	def CondorSolve.usage(str=nil)
		$stderr.puts "Usage: condor_solve.rb [options]\\"
		$stderr.puts "	-allCliques nJobs"
		$stderr.puts "	-resolveAll foo.conflict-debug"
		$stderr.puts "	-resolveAllPotential foo.conflict-debug (bad technique)"
		$stderr.puts "	-clique ip1 ip2 ... "
		$stderr.puts " 	-resolve ip1 ip2 model1 model2 [..]"
		$stderr.puts " 	-resolvePotential ip1 ip2 model1 model2 [..]"
		$stderr.puts "	-stats (on resolves hints)"
		$stderr.puts "\n#{str}" if str
		exit
	end
#########################################################################################
# these methods are invoked via condor on the client side of the call
	def CondorSolve.solveDlv(*args)
		str = args.join(' ')
		outdir = str2outdir(str)
		base = str2base(str)
		ENV['PATH'] += ":#{$sidecarDir}/scripts"
		
		Dir.mkSuperDir(outdir) unless Kernel::test(?d, outdir)	# create dir unless it exists
		return if(Kernel.test(?s,"#{outdir}/#{base}.model"))	# return if we've already done this
		dlvcmd="#{Data2dlvCmd} #{str} >  #{outdir}/#{base}.dlv"
		Kernel.system(dlvcmd) unless Kernel.test(?s,"#{outdir}/#{base}.dlv")
		Kernel.system("#{TestfactsCmd} #{outdir}/#{base}.dlv 2> /dev/null")
	end
################################################################
	def CondorSolve.solveSrcDstDlv(*args)
		# -srcdst srcip1 srcip2	dst1 [dst2 [...]]
		str = args[0..2].join(' ')
		outdir = str2outdir(str)
		base = str2base(str)
		ENV['PATH'] += ":#{$sidecarDir}/scripts"
		raise "Missing outdir #{outdir} !?!" unless Kernel::test(?d, outdir)
		src1=args[1]
		src2=args[2]
		cliquemodel=base.sub(/srcdst-/,'clique-') + ".model"
		fixmodel=base.sub(/srcdst-/,'fix-') + ".model"
		if File.test_and_size( outdir + '/' + fixmodel) > MinModelSize	# if a precomputed fixed file exists, 
			hints = outdir + '/' + fixmodel		# 	use that
		elsif File.test_and_size(outdir + '/' + cliquemodel) > MinModelSize # if a precomputed model file exists,
			hints = outdir + '/' + cliquemodel	# 	use that
		else
			hints=nil	# redundant; just for clarity
		end
		if hints
			localhints=File.basename(hints)
			Kernel.system("dumpmodel.sh -q #{hints} > #{localhints}")
		end
		args[3..-1].each { |dst|
			octet = dst.split(/\./)
			dstdir=octet[0] + '/' + octet[1]
			Dir.mkSuperDir("#{outdir}/#{dstdir}")
			dstbase=base+"-"+dst
			next if(File.test_and_size("#{outdir}/#{dstdir}/#{dstbase}.model")>MinModelSize)		# already done
			if hints
				dlvcmd="#{Data2dlvCmd} -sql \"" +
					"(src='#{src1}' and dst='#{dst}') or " + 
					"(src='#{src2}' and dst='#{dst}')\" "+
					">  #{dstbase}.dlv"
				Kernel.system("cat #{localhints} >> #{dstbase}.dlv")
			else
				# for some reason the src1 <--> src2 clique doesn't exist
				# 	compute everything at once
				dlvcmd="#{Data2dlvCmd} -sql \""+ 
					"(src='#{src1}' and dst='#{src2}') or " + 
					"(src='#{src2}' and dst='#{src1}') or " + 
					"(src='#{src1}' and dst='#{dst}') or " + 
					"(src='#{src2}' and dst='#{dst}') " +
					"\" >  #{dstbase}.dlv"
			end

			Kernel.system(dlvcmd) 
			Kernel.system("#{TestfactsCmd} #{dstbase}.dlv")
			# copy temp files back into place
			#Kernel.system("mv  #{dstbase}.dlv #{dstbase}.model #{outdir}/#{dstdir}/")	# don't put the dlv back for efficiency
			if(File.test_and_size(" #{dstbase}.model") > MinModelSize)
				Kernel.system("mv  #{dstbase}.model #{outdir}/#{dstdir}/") 
			else
				# useless model; don't bother writing
				File.delete(dstbase+".model")
			end
			File.delete(dstbase+".dlv")
		}
		Dir["core*"].each { |core|
			$stderr.puts "Found core file #{core}"
			Kernel.system("hostname >&2")
			Kernel.system("file #{core} >&2")
			$stderr.puts "Removing core file #{core}"
			File.delete(core)
		}
		if hints
			File.delete(localhints)
		end
	end
################################################################
	def CondorSolve.fixDlv(*args)
		cmd = args.shift
		hints = args.shift
		args.each { |model|
			ENV['PATH'] += ":#{$sidecarDir}/scripts"
			File.unlink(model) if Kernel.test(?f,model)
			dlv=model.sub(/\.model/,'.dlv')
			newdlv=dlv.sub(/\/clique-/,'/fix-')
			Kernel.system("cp #{dlv} #{newdlv}")
			Kernel.system("echo '% forced hints' >> #{newdlv}")
			Kernel.system("cat #{hints} >> #{newdlv}")
			Kernel.system("#{TestfactsCmd} #{newdlv}")
		}
	end
################################################################
	def CondorSolve.extractResolvedFacts(model,args)
		raise "Model #{model} missing" unless (Kernel.test(?f,model))
		str = args.join(' ')
		outdir = str2outdir(str)
		base = str2base(str)
		foundAlias=false
		foundLink=false
		ip1 = "ip"+ args[1].gsub(/\./,'_')
		ip2 = "ip"+ args[2].gsub(/\./,'_')
		linkRegexp = Regexp.new("link\\((#{ip1},#{ip2}|#{ip2},#{ip1})")
		aliasRegexp = Regexp.new("alias\\((#{ip1},#{ip2}|#{ip2},#{ip1})")
		File.open(model,"r").each { |line|
			line.split(/[\s{]+/).each { |fact|
				fact.sub!(/,$/,'')
				if linkRegexp.match(fact)
					foundLink=true
					#$stderr.puts "Link fact #{fact}"
				elsif aliasRegexp.match(fact)
					foundAlias=true
					#$stderr.puts "Alias fact #{fact}"
				end
			}
		}
		File.open("#{outdir}/#{base}.hints","w+") { |hints|
			if foundAlias && foundLink
				hints.puts "% unable to resolve #{args[1]} #{args[2]} multiple models"
			elsif foundAlias
				hints.puts "alias(#{ip1},#{ip2},resolved). " +
						"alias(#{ip2},#{ip1},resolved). % resolved"
			elsif foundLink
				hints.puts "link(#{ip1},#{ip2},0). % resolved"
			else
				hints.puts "% unable to resolve #{args[1]} #{args[2]} : no valid models"
			end
		}
	end
################################################################
	def CondorSolve.resolvePotentialDlv(args)
		# -resolvePotential ip1 ip2 file1 file2 [...]
		str = args.join(' ')
		outdir = str2outdir(str)
		base = str2base(str)
		ENV['PATH'] += ":#{$sidecarDir}/scripts"
		raise "Missing outdir #{outdir} !?!" unless Kernel::test(?d, outdir)
		if ! Kernel.test(?s,"#{outdir}/#{base}.dlv")
			File.open("#{outdir}/#{base}.dlv","w+") { |outfile|
				args[3..-1].each { |file|
					outfile.puts "% facts from #{file}"
					File.open("#{Basedir}/#{file}","r").each { |line|
						line.split.each { |fact|
							# translate link,alias,-alias facts to potentials
							case fact
							when /^link\((ip[\d_]+),(ip[\d_]+),(\d+)\)/
								outfile.puts "potentialLink(#{$1},#{$2},#{$3})."
							when /^alias\((ip[\d_]+),(ip[\d_]+),([\w\d]+)\)/
								outfile.puts "potentialAlias(#{$1},#{$2},#{$3})."
							when  /^-alias\((ip[\d_]+),(ip[\d_]+),([\w\d]+)\)/
								outfile.puts "potentialNotAlias(#{$1},#{$2},#{$3})."
							when /^offbyone/ , /^samePrefix/ , /^other/
								outfile.puts fact.sub(/,$/,'.')
							end
						}
					}
				}
			}
		end
		model="#{outdir}/#{base}.model"
		if(!Kernel.test(?s,model))
			Kernel.system("#{TestfactsCmd} #{outdir}/#{base}.dlv")	# generates .model file
		end
		CondorSolve.extractResolvedFacts(model,args)
	end
################################################################
	def CondorSolve.resolveDlv(*args)
		# -resolve ip1 ip2 file1 file2 [...]
		str = args.join(' ')
		outdir = str2outdir(str)
		base = str2base(str)
		ENV['PATH'] += ":#{$sidecarDir}/scripts"
		#raise "Missing outdir #{outdir} !?!" unless Kernel::test(?d, outdir)
		Dir.mkSuperDir(outdir)
		if ! Kernel.test(?s,"#{outdir}/#{base}.dlv")
			File.open("#{outdir}/#{base}.dlv","w+") { |outfile|
				args[3..-1].each { |file|
					file = file.sub(/\.model$/,'.dlv')
					outfile.puts "% data from #{file}"
					if File.test_and_size("#{Basedir}/#{file}")< DlvMinSize
						# srcdst-src1-src2-dst.dlv
						parts = File.basename(file).sub(/\.dlv$/,'').split(/-/)
						if parts[0] != 'srcdst'
							$stderr.puts "CondorSolve.resolveDlv:: Missing dlv file #{file} for non-srcdst job running #{args.join(' ')}: skipping"
							return
						end
						src1=parts[1]
						src2=parts[2]
						dst=parts[3]
						dlvcmd="#{Data2dlvCmd} -sql \""+ 
							"(src='#{src1}' and dst='#{src2}') or " + 
							"(src='#{src2}' and dst='#{src1}') or " + 
							"(src='#{src1}' and dst='#{dst}') or " + 
							"(src='#{src2}' and dst='#{dst}') " +
							"\" >  #{Basedir}/#{file}"
						Kernel.system(dlvcmd)
					end
					File.open("#{Basedir}/#{file}","r").each{ |line|
						outfile.puts line	# should be a 1 line way to do this
					}
				}
			}
		end
		model="#{outdir}/#{base}.model"
		if(!Kernel.test(?s,model))
			Kernel.system("#{TestfactsCmd} #{outdir}/#{base}.dlv")	# generates .model file
		end
		CondorSolve.extractResolvedFacts(model,args)
	end
################################################################
	def CondorSolve.parseArgs(argv)
		if argv[0] =~ /-allCliques/i
			CondorSolve.new.all_cliques(argv[1] ? argv[1].to_i : nil)
		elsif argv[0] =~ /-clique/i
			CondorSolve.solveDlv(argv)
		elsif argv[0] =~ /-resolveAll$/i
			CondorSolve.new.resolveAllConflicts("-resolve",*argv)
		elsif argv[0] =~ /-resolveAllPotential/i
			CondorSolve.new.resolveAllConflicts("-resolvePotential",*argv)
		elsif argv[0] =~ /-resolvePotential$/i
			CondorSolve.resolvePotentialDlv(argv)
		elsif argv[0] =~ /-srcdst$/i
			CondorSolve.solveSrcDstDlv(*argv)
		elsif argv[0] =~ /-fix$/i
			CondorSolve.fixDlv(*argv)
		elsif argv[0] =~ /-solveAll$/i
			CondorSolve.new.srcdstAll(argv[1]? argv[1].to_i : nil,argv[2] ? argv[2].to_i : nil)
		elsif argv[0] =~ /-fixAll$/i
			CondorSolve.new.fixAll(argv[1],argv[2]? argv[2].to_i : nil,argv[3] ? argv[3].to_i : nil)
		elsif argv[0] =~ /-resolve$/i
			CondorSolve.resolveDlv(*argv)
		elsif argv[0] =~ /-stats$/i
			CondorSolve.new.printHintsStats(argv[1])
		elsif argv[0] =~ /-batch$/i
			# -batch -resolve,arg1,arg2,arg3 -resolve,arg1,arg2,arg3
			argv.shift
			argv.each { |arg|	# everything but first arg
				CondorSolve.parseArgs(CondorSolve.unbatch(arg))
			}
		else
			CondorSolve.usage "Unknown mode #{argv[0]}: exiting"
		end
	end
################################################################
	def CondorSolve.unbatch(job)
		job.split(/:/)
	end
################################################################
	def CondorSolve.batch(jobs,batchsize)
		currentbatch="-batch "
		batchcount=0
		batches=Array.new
		jobs.each{ |job|
			currentbatch += " " + job.split.join(':')
			batchcount+=1
			if batchcount>= batchsize
				batches << currentbatch
				currentbatch="-batch "
				batchcount=0
			end
		}
		if batchcount > 0
			batches << currentbatch
		end
		return batches
	end
################################################################
end			# end of class definition




if $0 == __FILE__
	Thread.abort_on_exception = true        # to avoid threads silently dying
	$stderr.sync=true       # this should be redundant, but isn't
	CondorSolve.parseArgs(ARGV)
end
