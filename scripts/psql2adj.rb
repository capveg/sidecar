#!/usr/bin/ruby 


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


Usage="$0 {[sql-where-statement]|[-clique|-clique-quick ip1 ip2]}|-file ips"

require 'progressbar_mixin'

Data2dlv='data2dlv.pl'
Testfacts='test-facts.sh'
Dlv2adj='dlv2adj.pl'
Adj2map='adjacency2map.sh'
Verbose=false

MaxCPUs=7

raise Usage unless ARGV.length > 0
def print_and_run(str)
	puts str if Verbose
	Kernel.system(str)
end

def process(args)
	quick=false
	if args[0] == '-clique' or args[0] == '-clique-quick'
		raise Usage unless args.length == 3
		if args[0] == '-clique-quick'
			quick=true
		end
		query="(src='#{args[1]}' and dst='#{args[2]}') or (src='#{args[2]}' and dst='#{args[1]}')"
		if args[1] > args[2]	# cannonical IP first
			outfile="clique-#{args[1]}-#{args[2]}"
		else
			outfile="clique-#{args[2]}-#{args[1]}"
		end
	else
		query=args.join(" ")
		outfile=args.join("_")
		outfile.gsub!(/\s+/,'-')
		outfile.gsub!(/[^\w\d-]+/,'_')
	end

	if( !Kernel.test(?s,outfile+".model"))
		print_and_run("#{Data2dlv} -sql \"#{query}\" > #{outfile}.dlv")
		print_and_run("#{Testfacts} #{outfile}.dlv > #{outfile}.model")
		if ! quick 
			print_and_run("#{Dlv2adj} #{outfile}.model")
			adj=Dir.glob("#{outfile}*-1.adj")[0]
			puts "------------- Found #{adj}"
			print_and_run("#{Adj2map} #{adj}")
		end
	end
end

def processFile(file)
	$stderr.puts "Reading #{file} into memory"
	jobs= File.open(file).collect { |line|
		tokens=line.chomp.split
		tokens.unshift("-clique-quick")
	}
	$stderr.puts "Processing #{file} in #{MaxCPUs} jobs in parallel"
	jobs.each_inparallel_progress(MaxCPUs,"processing",true){ |args|
		process(args)
	}
end

if ARGV[0] == '-file'
	processFile(ARGV[1])
else
	process(ARGV)
end
