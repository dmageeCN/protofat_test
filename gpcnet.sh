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

: ${TEST:=all}
: ${NNODES:=$SLURM_NNODES}
: ${PPN:=32}

if [[ $TEST == 'all' ]]; then TEST='network_test,network_load_test'; fi

mkdir -p $LOGDIR

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

set_mpi_flags $NNODES $PPN
set_logs

RUNDIR=${LOGDIR}/${COMPILER}_${MPI}-${THEDATE}-${NAME}
mkcd $RUNDIR

run_test() {
    thistest=$1
    CMD="${THISDIR}/numa_wrapper.sh ${INSTALL_BASE}/bin/${thistest}"
    # echo "init_host,dest_host,bw" > $RUN_RSLT

    echo "GPCNET $thistest - NNODES: $NNODES" |& tee -a $RUN_LOG
    si=${SECONDS}

    echo "mpirun ${RUN_ARGS} ${CMD}" &>> $RUN_LOG
    mpirun ${RUN_ARGS} ${CMD} &> $RUN_TMP
    cat $RUN_TMP >> $RUN_LOG

    sf=$(( SECONDS-si ))
    echo "${thistest} took $sf seconds."
}

if [[ $TEST =~ 'network_test' ]]; then
    run_test 'network_test'
fi

if [[ $TEST =~ 'network_load_test' ]]; then
    run_test 'network_load_test'
fi

GPCNET_RSLT=$(echo $RUN_RSLT | sed 's/.csv//')
$THISDIR/parse_gpcnet.py $RUN_LOG --output=$GPCNET_RSLT

cd $CURDIR
