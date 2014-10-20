#!/usr/bin/perl -w

if( exists $ENV{"SIDECARDIR"})
{
	$scripts="$ENV{'SIDECARDIR'}/scripts";
}
else
{
	$scripts="$ENV{'HOME'}/swork/sidecar/scripts";
}

$TestFacts="$scripts/adaptiveDlv.rb";

$DoDLV=1;

#if(@ARGV>1)
$scratch=".";

$file = shift @ARGV || die "Usage: conflict-debug2dlv.pl foo.conflict-debug\n";
$JustTOP= shift @ARGV || 2;		# should we only use $JustTOP representative trace(s) from each faction?
					# $JustTOP ==0 implies use all traces
if($file eq "-d")
{
	$scratch=shift @ARGV;
	$file=shift @ARGV;
}
$base = $file;
$base =~s/.conflict-debug//;
$hints=$base.".hints";
$outdir="$scratch/$base.resolve-dir-top=$JustTOP";
$outfile="$base.conflict-debug.out";

unlink($hints);
unlink($outfile);
mkdir($outdir,0755);

open CONFLICT, "$file" or die "Open file $file: $!";
open HINTS, ">$hints" or die "Open file $hints: $!";
open OUTFILE, ">$outfile" or die "Open file $outfile: $!";
$nLines = `wc -l $file| awk '{print \$1}'`;
chomp $nLines;

$linecount=0;
$conflict=$good=$bad=0;
while(<CONFLICT>)
{
	$linecount++;
	# link(ip209_247_8_243,ip4_68_101_1) 3 alias(ip4_68_101_1,ip209_247_8_243) 17 (./planetlab1.atcorp.com./data-216.185.202.121:44955-164.107.127.13:80-612.model,./planetlab2.atcorp.com./data-216.185.202.123:34706-164.107.127.12:80-617.model

	#die "Malformed line $file:$linecount" unless(/\s+\(\s*(\S+)\s*\)\s+\(\s*(\S+)\s*\)/);
	@line = split;
	$line[5]=$line[6] if($line[5] eq "(");	# fix bug in spacing
	if($JustTOP>0)
	{
		@left = split /[;\(\)]+/,$line[4];
		shift @left if($left[0] eq "");
		#$traces[0]=$tmp[0];
		push @traces, @left[0..($JustTOP-1)];
		@right= split /[;\(\)]+/,$line[5];
		shift @right if($right[0] eq "");
		push @traces, @right[0..($JustTOP-1)];
	}
	else
	{
		@traces = split /[;\(\)]+/,$line[4];
		push @traces, split /[;\(\)]+/,$line[5];
	}
	die "bad conflict $linecount\n" unless($line[0] =~/link\(([^,\)]+),([^,\)]+)/);
	$t1=$1;
	$t2=$2;
	$outfilename= "conflict-$t1-$t2";
	# now everything is in @traces
	map {s/\.model/.dlv/} @traces;		# swap ".model" for ".dlv"
	chomp @traces;
	if(! -s  "$outdir/$outfilename.dlv" )	# don't create is already exists
	{
		# cat all the dlv files together
		open OUT, "|xargs cat | sort -u > $outdir/$outfilename.dlv" 
			or die "Couldn't open '|xargs cat | sort -u > $outdir/$outfilename.dlv':$!";
		print OUT join " ",@traces ;
		close OUT;
	}
	next unless($DoDLV);
	if(!-s "$outdir/$outfilename.model")	# skip this if it's already done
	{
		`$TestFacts $outdir/$outfilename.dlv`;		# try to create a model
		if ( $? != 0 )
		{
			die "$TestFacts $outdir/$outfilename.dlv died with some non-standard error"
		}
	}
	open MODEL, "$outdir/$outfilename.model" or die "Couldn\'t open $outdir/$outfilename.model:$!";
	$gotLinkFact=0;
	$gotAliasFact=0;
	# now that we've created a model, look through to see if the fact was resolved
	# this will trivially fail if the model is empty
	while(<MODEL>)
	{
		@facts=split /[\s{]+/;
		foreach $fact (@facts)
		{
			next unless($fact =~ /(link|alias)\(([^,\)]+),([^,\)]+)/);
			$ip1=$2;
			$ip2=$3;
			# strip out ips
			if((($t1 eq $ip1)&&($t2 eq $ip2)) ||
				(($t1 eq $ip2)&&($t2 eq $ip1)))	# if they are the ones we are interested in
			{
				if($1 eq "link")
				{
					$gotLinkFact=1;
				}
				else
				{
					$gotAliasFact=1;
				}
				$fact =~ s/[,}]$/./;
				$goodfact=$fact;
			}
		}
			
	}
	$date=`date`;
	chomp $date;
	if(($gotLinkFact && !$gotAliasFact)||(!$gotLinkFact && $gotAliasFact))
	{
		$good++;
		printf OUTFILE "$outdir/$linecount.model $good $bad $conflict SUCCESS $date ::%2.2f %%\n", 100*$linecount/$nLines;
		print HINTS "$goodfact\n";
	}
	elsif($gotLinkFact && $gotAliasFact)
	{
		$conflict++;
		printf OUTFILE "$outdir/$linecount.model $good $bad $conflict UNRESLV $date ::%2.2f %%\n", 100*$linecount/$nLines;
	}
	else
	{
		$bad++;
		printf OUTFILE "$outdir/$linecount.model $good $bad $conflict FAILURE $date ::%2.2f %%\n", 100*$linecount/$nLines;
	}
}

if($scratch ne ".")
{
	print "Removing $outdir\n";
	`rm -rf $outdir`;
}

