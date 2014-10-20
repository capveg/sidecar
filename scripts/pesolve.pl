#!/usr/bin/perl
#
# ./pesolve <output prefix> <dlv file>
# Takes translated passanger data file,
# parses it into pesolver
# and outputs pesolver results.
# Creates many temporary files with <output prefix> as a prefix.
#
# The end results will be put in <output prefix>.model and will be in DLV format.
# 
# WARNING: this script deletes/overwrites <output prefix>.{dlv,obj,model,output}

$name = shift or die "Not enough args.";
$file = shift or die "Not enough args.";
$base = shift || "$ENV{'HOME'}/swork/sidecar/solver/pesolver";

$olddir=`pwd`;
chomp $olddir;
$data = "$olddir/";

`rm -f $data/$name.dlv $data/$name.obj`;

print scalar localtime();

$maxkb = `grep MemTotal: /proc/meminfo | awk '{print \$2}'`;
chomp $maxkb;
$maxkb.="k";
$maxkb = "500m" if $maxkb eq "k";

# set non-absolute paths correctly.
$file = "$olddir/".$file if $file !~ /^\//;

$removenl = 'perl -ne \'chomp; print; print " "\'';

print scalar localtime();
print " Running solver...\n";
# run the solver with the data file as input.
# Solver output is adjacency graph.
print "cd $base/build && java -Xmx$maxkb classifier.sidecar.DlvToESObj $file $data/$name.obj | tee $data/$name.output\n";
`cd $base/build && java -Xmx$maxkb classifier.sidecar.DlvToESObj $file $data/$name.obj | tee $data/$name.output`;
print scalar localtime();
print " Finished computation, printing to $data/$name.model\n";
$modelComments =`cd $base/build && java -Xmx$maxkb classifier.sidecar.DlvESObj $data/$name.obj | grep "^%" | tee $data/$name.model`;
`echo -n "Best model: {" >> $data/$name.model`;
`cd $base/build && java -Xmx$maxkb classifier.sidecar.DlvESObj $data/$name.obj | grep "^[^%]" | $removenl >> $data/$name.model`;
print scalar localtime();
print " Doing dumb-processing (traceroute links, mostly), printing to $data/$name.model\n";
`cd $base/build && java -Xmx$maxkb classifier.sidecar.DLVTOFactory $file | $removenl >> $data/$name.model`;
`grep type $file | $removenl >> $data/$name.model`;
`grep other $file | $removenl >> $data/$name.model`;
`grep alias $file | $removenl >> $data/$name.model`;
`grep link $file | $removenl >> $data/$name.model`;
`echo "}" >> $data/$name.model`;
`echo 'Cost (filler) <[$1:0]>' >> $data/$name.model` if $modelComments=~/Explanation cost (\d+)/;
print scalar localtime();
print " Finished!\n";


