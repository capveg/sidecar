#!/usr/bin/ruby

ip = ARGV[0]

in_fname = ip+".out"
gplot_fname = "gplot-temp"
eps_fname = ip+".eps"

outf = File.new(gplot_fname, "w+")
PLOT = <<EOF
set out "EPSFNAME"
set term postscript color eps "Helvetica" 15

set key left

set xlabel "Time"
set ylabel "IP ID"

plot "INFNAME" title "Observed" #, "INFNAME" u 1:3 title "Estimated" w li

EOF

##----------------

outf.puts PLOT.gsub('INFNAME', in_fname).gsub('EPSFNAME', eps_fname)
outf.close

`gnuplot #{gplot_fname}`

`gv #{eps_fname}`
