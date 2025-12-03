#!/bin/bash

alias gcl='git clone --recurse-submodules'

THISFILE=${BASH_SOURCE[0]}
: ${THISFILE:=$0}

THISDIR=$(dirname $(realpath ${THISFILE}))
mkdir -p ${THISDIR}/src && cd ${THISDIR}/src

if [[ ! (-d ${PWD}/GPCNET) ]]; then
    gcl https://github.com/dmageeCN/GPCNET.git
fi
if [[ ! (-f ${PWD}/osu-micro-benchmarks-7.5.1.tar.gz) ]]; then
    wget https://mvapich.cse.ohio-state.edu/download/mvapich/osu-micro-benchmarks-7.5.1.tar.gz
fi

ln -sfn /bfs3/sw/gromacs .
ln -sfn /bfs3/sw/namd .
ln -sfn /bfs3/sw/wrf .
# gcl https://github.com/intel/mpi-benchmarks.git