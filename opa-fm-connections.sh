#!/bin/bash

rfile=/tmp/.opa-route-$1-$2
tmp_route=/tmp/.tmp.route

opareport -o route -S nodepat:"$1 hfi1_0" -D nodepat:"$2 hfi1_0" &> $rfile

startline=$(grep -n $1 $rfile | tail -n2 | head -n1 | sed 's/:/ /g' | awk '{print $1}')
endline=$(grep -n $2 $rfile | tail -n2 | head -n1 | sed 's/:/ /g' | awk '{print $1}')

nlines=$((endline-startline+1))
nhops=$((nlines/2-1))

if [ "$nhops" = "3" ];then

    head -n $endline $rfile | tail -n $nlines | awk '{print $3,$5}' > $tmp_route

    sndedge=$(head -n2 $tmp_route | tail -n1 | awk '{print $2}')
    sndedgein=$(head -n2 $tmp_route | tail -n1 | awk '{print $1}')
    sndedgeout=$(head -n3 $tmp_route | tail -n1 | awk '{print $1}')
    core=$(head -n4 $tmp_route | tail -n1 | awk '{print $2}')
    corein=$(head -n4 $tmp_route | tail -n1 | awk '{print $1}')
    coreout=$(head -n5 $tmp_route | tail -n1 | awk '{print $1}')

    rcvedge=$(head -n6 $tmp_route | tail -n1 | awk '{print $2}')
    rcvedgein=$(head -n6 $tmp_route | tail -n1 | awk '{print $1}')
    rcvedgeout=$(head -n7 $tmp_route | tail -n1 | awk '{print $1}')

    echo $1 $2 $sndedge $sndedgein $sndedgeout $core $corein $coreout $rcvedge $rcvedgein $rcvedgeout

else
 echo "nhops must = 3 but  it's $nhops"
 echo "start $startline end: $endline"
fi

#rm $tmp_route
#rm .opa-route-*
