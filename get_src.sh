#!/bin/bash

gcl() {
    git clone --recurse-submodules "$1"
}

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

### MAKE VENV
VENV_DIR=${THISDIR}/installs/protofat_venv
if [[ ! (-d $VENV_DIR) ]]; then
    python3 -m venv $VENV_DIR
    source $VENV_DIR/bin/activate
    python3 -m pip install --upgrade pip
    pip3 install pandas scipy numpy matplotlib ipython
fi