#!/bin/bash

export NAME=GPCNET

THISFILE=${BASH_SOURCE[0]}
: ${THISFILE:=$0}

export THISDIR=$(dirname $(realpath ${THISFILE}))

if [[ ! (-f ${THISDIR}/util.sh) ]]; then
    echo YOU NEED util.sh in the same directory as this script
    echo in order to run this test
    exit 1
fi

source ${THISDIR}/util.sh

# SET COMMAND LINE OPTIONS
setvar "$@"

# SET DEFAULT OPTIONS THAT APPLY FOR EVERY TEST
universal_opts

: ${TEST:=network_test}
: ${NNODES:=$SLURM_NNODES}
: ${PPN:=32}

export COMPILER MPI INSTALL_BASE SRC_BASE 
export FI_PROV VERBOSE TEST NNODES PPN LOGDIR

mkdir -p $LOGDIR

PROCS=$(( PPN*NNODES ))

set_compiler_mpi

###############
# BUILD
###############

if [[ $REBUILD == 'true' ]]; then rm -rf $INSTALL_BASE; fi

if [[ ! (-d $INSTALL_BASE) ]]; then
    set -e
    mkdir -p $(dirname ${INSTALL_BASE})
    export PREFIX=${INSTALL_BASE}
    cd ${SRC_BASE}/${NAME}
    make clean
    BUILD_LOG=${LOGDIR}/${COMPILER}_${MPI}-${NAME}-build.log
    echo ${THEDATE} | tee $BUILD_LOG
    make FLAGS="-DVERBOSE" install |& tee -a $BUILD_LOG
    cd $CURDIR
    set +e
fi

###############
# RUN
###############

CMD=${INSTALL_BASE}/bin/${TEST}

set_ompi_flags $NNODES $PPN
set_logs

# echo "init_host,dest_host,bw" > $RUN_RSLT

echo "GPCNET $TEST - NNODES: $NNODES"
si=${SECONDS}

RUNDIR=${LOGDIR}/${COMPILER}_${MPI}-${THEDATE}-${NAME}
mkcd $RUNDIR
echo "mpirun ${RUN_ARGS} ${CMD}" &>> $RUN_LOG
mpirun ${RUN_ARGS} ${CMD} &> $RUN_TMP
cat $RUN_TMP >> $RUN_LOG

sf=$(( SECONDS-si ))
echo "${NAME} took $sf seconds."

cd $CURDIR