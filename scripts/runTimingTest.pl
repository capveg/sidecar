#!/usr/bin/perl


sub getRuntime {
    my $timefile = shift;
    open TIME,"<$timefile";
    my $tm = -1;
    while (<IN>) {
        $tm = $1 if (/([\d\.]+)user/);
    }
    return $tm;
}

foreach $file (@ARGV) {
    chomp ($lines = `wc -l $file`);
    print `/usr/bin/time -o time.out pesolve.pl $file-run $file`;
    $time = &getRuntime "time.out";
    print "TIMELINE\t$lines\t$time\n";
}
