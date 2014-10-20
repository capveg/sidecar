#!/bin/sh
range="0-20"
#../test-constraints.pl -typeN 1 -typeH 4 -badAliasMerc 3 -badAliasName 2 -badAlias $range -offbyoneAlias $range -offbyoneLink $range `cat dlvorder` | tee constraints.out


# hand tuned
 ../test-constraints.pl -NoUnlink -typeN 1 -typeH 4 -badAliasMerc 3 -badAliasName 2 -badAlias 2 -offbyoneAlias 5 -offbyoneLink 5 `cat dlvorder`
