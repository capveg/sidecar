#!/usr/bin/perl -w
use Getopt::Long;

# set ts=4 (!!!)

sub usage
{
	my ($msg)=@_;
	print STDERR "$msg\n" if($msg);
	print STDERR << "EOF";
test-constraints.pl [options] [f1.dlv [f2.dlv [...]]]
	-noUnlink			-- don't remove tmp files
	-dir dir				-- read dlvfiles in dir
	-typeN range 			- penalty for each type N router
	-typeH range 			- penalty for each type H router
	-badAliasMerc range		- penalty for violating Mercator alias
	-badAliasName range		- penalty for violating undns alias
	-badAlias range			- penalty for violating ipid alias
	-offbyoneAlias range		- penalty for aliasing two offbyone ips (push apart)
	-offbyoneLink range		- penalty for not linking two offbyone ips (pull together)

where "range" is either "X" or "X-Y" X,Y \\in [0:255]
test all possible contraints in the specified ranges and output the contraints
that match fX.model or fX.adj forall X in f1...fN
EOF
	exit 0
}

if( !defined $ENV{"HOME"})
{
	        $ENV{"HOME"}=".";       # stoopid hack to shut up complaints in condor
		                                # b/c it doesn't set $HOME
}


$timeout=60;	# max length we let a dlv process run
$Default=5;
$NoUnlink=0;

$typeNRange=$Default;
$typeHRange=$Default;
$badAliasMercRange=$Default;
$badAliasNameRange=$Default;
$badAliasRange=$Default;
$offbyoneAliasRange=$Default;
$offbyoneLinkRange=$Default;

$constraintsDir=".";

if( ! defined($ENV{"SIDECARDIR"}))
{
	$ENV{"SIDECARDIR"}=$ENV{"HOME"}."/swork/sidecar";
}


#GetOptions("o"=>\$oflag,
#				"verbose!"=>\$verboseornoverbose,
#				"string=s"=>\$stringmandatory,
#				"optional:s",\$optionalstring,
#				"int=i"=> \$mandatoryinteger,
#				"optint:i"=> \$optionalinteger,
#				"float=f"=> \$mandatoryfloat,
#				"optfloat:f"=> \$optionalfloat);

GetOptions(
		"noUnlink" => \$NoUnlink,
		"typeN:s" => \$typeNRange,
		"dir:s" => \$constraintsDir,
		"typeH:s" => \$typeHRange,
		"badAliasMerc:s" => \$badAliasMercRange,
		"badAliasName:s" => \$badAliasNameRange,
		"badAlias:s" => \$badAliasRange,
		"offbyoneAlias:s" => \$offbyoneAliasRange,
		"offbyoneLink:s" => \$offbyoneLinkRange);





$typeNMin=getMin($typeNRange);
$typeNMax=getMax($typeNRange);
$typeHMin=getMin($typeHRange);
$typeHMax=getMax($typeHRange);
$badAliasMercMin=getMin($badAliasMercRange);
$badAliasMercMax=getMax($badAliasMercRange);
$badAliasNameMin=getMin($badAliasNameRange);
$badAliasNameMax=getMax($badAliasNameRange);
$badAliasMin=getMin($badAliasRange);
$badAliasMax=getMax($badAliasRange);
$offbyoneAliasMin=getMin($offbyoneAliasRange);
$offbyoneAliasMax=getMax($offbyoneAliasRange);
$offbyoneLinkMin=getMin($offbyoneLinkRange);
$offbyoneLinkMax=getMax($offbyoneLinkRange);


if(-f "$constraintsDir/dlvorder")
{
		open F,"$constraintsDir/dlvorder" or die "open: $constraintsDir/dlvorder :$!";
		while(<F>)
		{
				chomp;
				push @ARGV,"$constraintsDir/".$_;
		}
		close F;
}
else
{
		print STDERR " -- constraintsDir specified but no dlvorder found: hope that's okay\n";
		push @ARGV,<$constraintsDir/*.dlv>;
}

usage() if(@ARGV==0);

for($typeN=$typeNMin;$typeN<=$typeNMax;$typeN++)
{
	for($typeH=$typeHMin;$typeH<=$typeHMax;$typeH++)
	{
		for($badAliasMerc=$badAliasMercMin;$badAliasMerc<=$badAliasMercMax;$badAliasMerc++)
		{
			for($badAliasName=$badAliasNameMin;$badAliasName<=$badAliasNameMax;$badAliasName++)
			{
				for($badAlias=$badAliasMin;$badAlias<=$badAliasMax;$badAlias++)
				{
					for($offbyoneAlias=$offbyoneAliasMin;$offbyoneAlias<=$offbyoneAliasMax;$offbyoneAlias++)
					{
						for($offbyoneLink=$offbyoneLinkMin;$offbyoneLink<=$offbyoneLinkMax;$offbyoneLink++)
						{
							$passed=1;
							$saveddlv="";
							foreach $dlv (@ARGV)
							{
								if(!&testContraints($dlv,
											$typeN,$typeH,$badAliasMerc,
											$badAliasName,$badAlias,$offbyoneAlias,
											$offbyoneLink))
								{
										$passed=0;
										$saveddlv=$dlv;
										last;
								}
							}
							if($passed==1)	# needs to have passed all dlvs to be here
							{
									print "PASSED typeN=$typeN typeH=$typeH badAliasMerc=$badAliasMerc badAliasName=$badAliasName".
										" badAlias=$badAlias offbyoneAlias=$offbyoneAlias offbyoneLink=$offbyoneLink\n";
							}
							else
							{
									print "FAILED typeN=$typeN typeH=$typeH badAliasMerc=$badAliasMerc badAliasName=$badAliasName".
										" badAlias=$badAlias offbyoneAlias=$offbyoneAlias offbyoneLink=$offbyoneLink -- $saveddlv\n";
							}
						}
					}
				}
			}
		}
	}
}


######## run the given $dlv file with the given constraints;
#	return 1 if matches desired output, 0 otherwise

sub testContraints
{
		my ( $dvl, $typeN,$typeH,$badAliasMerc, $badAliasName,$badAlias,$offbyoneAlias, $offbyoneLink)=@_;
		$filename="contraints-$typeN,$typeH,$badAliasMerc,$badAliasName,$badAlias,$offbyoneAlias,$offbyoneLink.test-dlv";
		open CONSTRAINTS,">$filename" or die "Couldn't open $filename:$!";
		# create the contraints file
		print CONSTRAINTS << "EOF";
%%%%% Begin of contraints file
% Example of a "weak constraint": try to come up with models
%	where these things don't happen
% 	the [3:1] means give ruleset level 1 a weight of 3
% 	solver prefers models with the least weight at the least ruleset

% First, mark all used IP addresses
usedIp(IP):-alias(IP,_,_).
usedIp(IP):-alias(_,IP,_).
usedIp(IP):-link(IP,_,_).
usedIp(IP):-link(_,IP,_).

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Level 10: really important
% really try to avoid links between things that are aliased: weight=10, level=5
:~ alias(X,Y,_), link(X,Y,_). [1:10]
:~ alias(X,Y,_), link(Y,X,_). [1:10]
%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Level 7 : fairly important
% The only Type C routers we have should come from data2dlv.pl
%	Don't let dlv infer new typeC routers
% try to avoid type C routers: weight =1 , level=7
:~ type(IP,c).	[1:7]

%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%%
% Level 5 : main area of contention
% try to avoid hidden routers: weight =$typeH, level=5
:~ type(IP,h).	[$typeH:5]

% try to avoid assigning aliases to off-by-one IP addreses: weight=$offbyoneLink, level=5
			% important that this weigh more then hidden router cost
:~ alias(X,Y,_), offbyone(X,Y). [$offbyoneAlias:5] %%% data2dlv generates both pairs
% also try to avoid them for transitive aliases
:~ alias(X,Z,_), alias(Z,Y,_), offbyone(X,Y). [$offbyoneAlias:5]
:~ alias(X,Z,_), alias(Y,Z,_), offbyone(X,Y). [$offbyoneAlias:5]
:~ alias(Z,X,_), alias(Z,Y,_), offbyone(X,Y). [$offbyoneAlias:5]

%% penalize things that don't bring offbyone addresses together: weight=$offbyoneLink, level=5
:~ offbyone(IP1,IP2),not link(IP2,IP1,1),tr(ID,_,_,IP1,_),rr(ID,1,IP2). [$offbyoneLink:5]	% if IP1 is type A
:~ offbyone(IP1,IP2),not link(IP2,IP1,1),tr(ID,_,_,IP1,_),rr(ID,2,IP2). [$offbyoneLink:5]	% if IP1 is type B

%% try to avoid overriding aliases from DB
:~ badAlias(X,Y,mercatorsource). [$badAliasMerc:5]
:~ badAlias(X,Y,name). [$badAliasName:5]		% aliases from 'name', i.e., DNS are most questionable
:~ badAlias(X,Y,Z),Z!=mercatorsource,Z!=name. [$badAlias:5]
%% try to avoid overriding notaliases from DB
:~ badNotAlias(X,Y,Z),Z!=name,Z!=mercatorsource. [$badAlias:5]
:~ badNotAlias(X,Y,name). [$badAliasName:5]		% aliases from 'name', i.e., DNS are most questionable
:~ badNotAlias(X,Y,mercatorsource). [$badAliasMerc:5]		% aliases from 'mercatorsource' are more reliable

%% try to avoid type N routers: weight =1, level=5
:~ type(IP,n).	[$typeN:5]
EOF
	close CONSTRAINTS;

	my ($model, $gooddiff,$result,$base,$err,$adj,@adjs,@errs);
	chomp $dlv;
	$base=`basename $dvl`;
	chomp $base;
	$base=~s/\.dlv$//;
	$err="$base.err";
	$model="$base.model";
	$result=1;
	# run the solver with a timeout, output model to foo.model and errors to foo.err
	die "Couldn't find $dlv\n" unless(-f $dlv);
	$ENV{"CONSTRAINTS"}=$filename;
	system("$ENV{'SIDECARDIR'}/scripts/timer $timeout $ENV{'SIDECARDIR'}/scripts/test-facts.sh $dlv 2> $err > $model");
	$result=0 if( -s $err);		# any errors means it failed or timedout
	$result=0 if(! -s $model);	# no model == automatic failure
	if($result==1)			# if no problems yet,
	{
		system("$ENV{'SIDECARDIR'}/scripts/dlv2adj.pl -q $model");
		@adjs=<$base-C*>;	# get a list of all files matching glob $base-*
		$gooddiff=1;		# assume no match to begin with
		foreach $adj (@adjs)
		{
			if($gooddiff)
			{
				open DIFF, "$ENV{'SIDECARDIR'}/scripts/diffadj.pl $constraintsDir/$base.good-dlv $adj|" or die "error openning diffadj $base.good-dlv $adj| :$!";
				@errs=<DIFF>;
				$gooddiff=0 if(@errs!=0);	# DESIGN DECISION: all diffs need to be good
								# for us to consider this to be a valid set of weights
			}
			unlink($adj) unless($NoUnlink);			# clean up as we go
		}	
		$result=0 unless($gooddiff==1);
	}
	if(!$NoUnlink)
	{
		unlink($model);
		unlink($err);
		unlink($filename) ;#unless($result==1);		# leave the valid files around
	}
	return $result;
}

# takes "4" or "1-5" and returns the bottom of the range, i.e., "4" or "1"
sub getMin
{
	my ($str,@line)=@_;
	@line=split /-/,$str;
	return $line[0];
}
# takes "4" or "1-5" and returns the top of the range, i.e., "4" or "5"
sub getMax
{
	my ($str,@line)=@_;
	@line=split /-/,$str;
	if(@line==1)
	{
		return $line[0];
	}
	else
	{
		return $line[1];
	}
}
