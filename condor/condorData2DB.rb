#!/usr/bin/ruby

###############################################
# Use Condor to adaptiveDlv solve stuff
#	store intermediate files for resolving w.x.y.z and a.b.c.d
#	into w/x/a/b/data-w.x.y.z-a.b.c.d.dlv and w/x/a/b/data-w.x.y.z-a.b.c.d.model
#

$sidecarDir=ENV['SIDECARDIR'] ? ENV['SIDECARDIR'] : "#{ENV['HOME']}/swork/sidecar"
$libDir="#{$sidecarDir}/ip2ttls2db"

$: << "#{$sidecarDir}/random_prober"
$: << "#{$sidecarDir}/scripts"
$: << "#{$sidecarDir}/scripts/ruby"
$: << "#{$sidecarDir}/condor"
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

require 'condorSolve'

class CondorData2DB
	DefaultNJobs=10
	Outdir='/fs/sidecar/condor/data2db.outdir'

###########################################################################
	def initialize(dir)
		@dir=dir
		raise "#{dir} does not exists " unless Kernel::test(?d,dir) || Kernel::test(?f,dir)
	end
###########################################################################
	def inputAll(maxJobs=nil)
		maxJobs=DefaultNJobs unless maxJobs	# b/c we might have been called with nil
		if Kernel::test(?d,@dir)
			queue = IO.popen("find #{@dir} -name \\*.tar.gz").collect { |line|
				line.chomp
			}
		else	
			raise "weirdness" unless Kernel::test(?f,@dir)	# read tarballs from file
			queue = File.open(@dir,"r").collect { |line|
				line.chomp
			}
		end
		raise "Need to create #{Outdir}" unless Kernel::test(?d,Outdir)
		$stderr.puts "Found #{queue.length} tarballs to input"
		logfilename="condorData2DB.log." + Time.now.to_s.gsub(/\s+/,'_')
		logfile = File.open(logfilename,"w+")
		$stderr.puts "Redirecting stdout to #{logfilename}"
		$stdout.reopen(logfile)
		start=Time.now
		$stderr.puts "Start time: #{start} "
		Dir.mkSuperDir("/tmp/capveg")
		queue.each_inparallel_progress(maxJobs,"Tarballs",true){ |str|
			condor_spawn_and_wait(str)
		}
		finish=Time.now
		$stderr.puts "Finish time: #{finish}"
		$stderr.puts "Ellapsed seconds : #{(finish-start).to_f}"
	end
###########################################################################
	def condor_spawn_and_wait(str)
		base = str.sub(/^\.\/?/,'').gsub(/\//,'_')
		commandone = "condor_submit "+
					"-a File='#{str}' " + 
					"-a OutputDir='#{Outdir}' "+
					"-a Base='#{base}' " +
					" /fs/sidecar/condor/condorData2DB-template.cmd 2>&1 " 
		commandtwo = "condor_wait %s/%s.log 2>&1 " % [ Outdir, base]
		if Kernel::system(commandone)  then
			Kernel::system(commandtwo)
		else
			raise "job submission failed for #{commandone}"
		end
	end
end
###########################################################################
if $0 == __FILE__
	Thread.abort_on_exception = true        # to avoid threads silently dying
	$stderr.sync=true       # this should be redundant, but isn't
	if ARGV[0] =~ /-inputAll/i	
		CondorData2DB.new(ARGV[1]).inputAll(ARGV[2] ? ARGV[2].to_i : nil)
	else
		$stderr.puts "Unknown mode #{ARGV[0]}: exiting"
		$stderr.puts "#{$0} -inputAll /path/to/dir"
	end
end
