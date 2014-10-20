#!/bin/sh

if [ -z $SIDECARDIR ]; then
	SIDECARDIR=$HOME/swork/sidecar
fi

filter="-filter=other,type,alias,link,badAlias,badNotAlias,badLink,problemProbePair"
if [ -z $CONSTRAINTS ]; then
	constraints=$SIDECARDIR/solver/constraints.dlv 
else
	constraints=$CONSTRAINTS
fi
output=-silent

#ODBC=-odbc


if [ "X$1" == "X" ]; then
	echo "Usage: test-facts.sh facts.dlv" >&2
	exit 1
fi
if [ "X$1" == "X-v" ]; then
	filter=-nofacts
	shift 
fi
if [ "X$1" == "X-V" ]; then
	output=-wctrace
	echo Running with -wctrace
	shift 
fi

# auto generate transitions
if [ $SIDECARDIR/solver/gen_transitions.pl -nt $SIDECARDIR/solver/transitions.dlv ] ; then
	$SIDECARDIR/solver/gen_transitions.pl > $SIDECARDIR/solver/transitions.dlv
fi


exec $SIDECARDIR/scripts/dlv $ODBC $output $filter $@ \
$SIDECARDIR/solver/types.dlv \
$constraints  $SIDECARDIR/solver/strong.dlv \
$SIDECARDIR/solver/classifications.dlv \
$SIDECARDIR/solver/tiebreaker.dlv \
$SIDECARDIR/solver/potentialAliases.dlv \
$SIDECARDIR/solver/gaps.dlv \
$SIDECARDIR/solver/transitions.dlv 
exit 0
