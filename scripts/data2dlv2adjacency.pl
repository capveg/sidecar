#!/usr/bin/perl -w
# 	./data2dlv2adj.pl [-h hintfile] [-v] [-] [data1 [data2 [..]]]

$hintfile="";

# nspring added.
if(@ARGV==0) {
  printf STDERR "usage: data2dlv2adjacency.pl [-h hintfile] [-v] [-] [data1 [data2 [..]]]\n";
  exit;
}

if((@ARGV>=2)&&($ARGV[0] eq "-h"))
{
	shift @ARGV;
	$hintfile=$ARGV[0];
	shift @ARGV;
	print STDERR "Using $hintfile as a hint file\n";
}

if((@ARGV>=1)&&($ARGV[0] eq "-v"))
{
	shift @ARGV;
	$Verbose=1;
}
if((@ARGV>=1)&&($ARGV[0] eq "-"))
{
	shift @ARGV;
	push @ARGV,<>;
}

$filecount=0;
foreach $file (@ARGV)	# foreach file
{
	chomp $file;
	$filecount++;
	$percent = 100*$filecount/@ARGV;
	printf(STDERR "\r%8.6f done",$percent) unless($filecount%10 || $Verbose);
	`data2dlv.pl $file > $file.dlv`;
	print "data2dlv.pl $file > $file.dlv\n" if($Verbose);
	`test-facts.sh $hintfile $file.dlv > $file.model`;
	print "test-facts.sh $file.dlv > $file.model\n" if($Verbose);
	`dlv2adj.pl $file.model`;
	print "dlv2adj.pl $file.model\n" if($Verbose);
}
