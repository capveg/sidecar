#!/usr/bin/ruby -I..

low=0
high=10
range="#{low}-#{high}"
maxjobs=200

test=false

require "nspring-utils.rb"
require "progressbar.rb"


test=true if "-test" == ARGV[0]

options=Array.new
#!/bin/sh
#range="0-20"
#../test-constraints.pl -typeN $range -typeH $range -badAliasMerc $range -badAliasName $range -badAlias $range -offbyoneAlias $range -offbyoneLink $range `cat dlvorder` | tee constraints.out

if(!test)
	low.upto(high){ |offbyone|
		low.upto(high){ |typeH|
			low.upto(high){ |badAliasMerc|
				options << "-typeN #{range} " +
					"-typeH #{typeH} " +
					"-badAliasMerc  #{badAliasMerc} " +
					"-badAliasName #{badAliasMerc} "+
					"-badAlias #{badAliasMerc} "+
					"-offbyoneAlias #{offbyone} "+
					"-offbyoneLink #{offbyone} " +
					"-dir /fs/sidecar/scripts/constraints"
			}
		}
	}
else
	$stderr.puts "Runnging in test mode: should get a PASSED"
	options << "-NoUnlink -typeN 1 " +
		"-typeH 4 " +
		"-badAliasMerc  3 " +
		"-badAliasName 2 "+
		"-badAlias 2 "+
		"-offbyoneAlias 5 "+
		"-offbyoneLink #{range} " +
		"-dir /fs/sidecar/scripts/constraints"
end

cleancmd="find . -name outfile\* -o -name errfile\* -o -name logfile\* -o -name \*.adj -o -name \*.err -o -name \*.test-dlv | xargs rm -f"
cmd="./condor_submit_and_wait-constraints"

$stderr.puts "Running clean cmd #{cleancmd}"
Kernel::system(cleancmd)

if !Kernel::test(?f, cmd)
	cmd="."+cmd
	if !Kernel::test(?f, cmd)
		$stderr.puts "couldn't find #{cmd} (even looked up a directory)"
		exit 1
	end
end

options.each_inparallel_progress(maxjobs,"Jobs",true){ |opt|
	Kernel::system(cmd + " " + opt + " 2>&1")
}
