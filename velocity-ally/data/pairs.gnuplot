set out "pairs.eps"
set term postscript color eps "Helvetica" 30

set log yx
set key left

set xlabel "Pair rank"
set ylabel "Difference in Slope between two IPs"

plot \
"pairs-alias-plot.sort" u 0:1 title "alias" , \
"pairs-not-plot.sort" u 0:1 title "not alias"  
#"pairs-unknown-plot.sort" u 0:1 title "unknown"  \
