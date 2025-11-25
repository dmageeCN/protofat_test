#!/bin/bash

export NAME=FABRIC-CONNECT

THISFILE=${BASH_SOURCE[0]}
: ${THISFILE:=$0}

export THISDIR=$(dirname $(realpath ${THISFILE}))

if [[ ! (-f ${THISDIR}/util.sh) ]]; then
    echo YOU NEED util.sh in the same directory as this script
    echo in order to run this test
    exit 1
fi

source ${THISDIR}/util.sh

setvar "$@"

node_by_edge
for en1 in $(echo ${EDGEARRAY[1]} | tr ',' '\n'); do
    for en2 in $(echo ${EDGEARRAY[2]} | tr ',' '\n'); do
        ${THISDIR}/opa-fm-connections.sh $en1 $en2
    done        
done