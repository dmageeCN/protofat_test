#!/bin/bash

export NAME=osumb

link_executables() {
    olddir=$PWD
    idir=$1
    bindir=$idir/bin
    mkcd -p $bindir
    for x in $(find $idir -type f -executable); do
        ln -sfn $x .
    done
    cd $olddir
}

# SAVE FULL OSU_BW output to columns of csv.
save_full_rslt() {
    fulloutput=$1
    result_csv=$2
    header=$3
    tmp_file=/tmp/output_osu.tmp
    echo $header > $tmp_file
    
    awk '/# Size.*Bandwidth/ {flag=1; next} flag && /^[0-9]+[[:space:]]+[0-9.]+/ {print $1","$2}' "$fulloutput" >> $tmp_file
    if [[ -f $result_csv ]]; then
        paste -d',' "$result_csv" <(cat $tmp_file | cut -d',' -f2) > ${tmp_file}.2
        mv ${tmp_file}.2 ${tmp_file}
    fi

    mv $tmp_file $result_csv
    rm -rf ${tmp_file} ${tmp_file}.2
}

THISFILE=${BASH_SOURCE[0]}
: ${THISFILE:=$0}

THISDIR=$(dirname $(realpath ${THISFILE}))

if [[ ! (-f $THISDIR/util.sh) ]]; then
    echo YOU NEED util.sh in the same directory as this script
    echo in order to run this test
    exit 1
fi

source $THISDIR/util.sh

setvar "$@"

: ${COMPILER:=intel}
: ${MPI:=intel}
: ${INSTALL_BASE:=${THISDIR}/installs/${NAME}-${COMPILER}_${MPI}}
: ${BUILD_BASE:=/tmp/build_${NAME}/${COMPILER}_${MPI}}
: ${SRC_BASE:=${THISDIR}/src}
: ${FI_PROV:=default}
: ${VERBOSE:=false}
: ${LOGDIR:=${PWD}/${NAME}_protofat_result}
: ${TEST=osu_bw}
: ${PPN:=1}
: ${NNODES=2}
: ${CMD_ARGS:='-i 10 -m 4:67108864'}
: ${ALGO:=default}
: ${HISET:=''} # SET NODE TO TEST AGAINST ALL OTHER NODES.

export COMPILER MPI INSTALL_BASE BUILD_BASE SRC_BASE 
export FI_PROV VERBOSE LOGDIR HISET

mkdir -p $LOGDIR

PROCS=$(( PPN*NNODES ));
export RUN_ARGS="-np $PROCS " # --map-by ppr:${PPN}:node "

set_compiler_mpi

###############
# BUILD
###############

if [[ $REBUILD == 'true' ]]; then rm -rf $INSTALL_BASE; fi

if [[ ! (-d $INSTALL_BASE) ]]; then
    mkdir -p $(dirname ${INSTALL_BASE})
    BUILD_TOP=$(dirname $BUILD_BASE)
    mkcd $BUILD_TOP
    TAR_NAME="osu-micro-benchmarks-7.5.1"
    tar xzf ${SRC_BASE}/${TAR_NAME}.tar.gz
    mkcd $BUILD_BASE
    BUILD_LOG=${LOGDIR}/${COMPILER}_${MPI}-${NAME}-build.log
    $BUILD_TOP/${TAR_NAME}/configure --prefix=${INSTALL_BASE} |& tee -a $BUILD_LOG
    echo ${THEDATE} | tee $BUILD_LOG
    make -j 16 install |& tee -a $BUILD_LOG
    cd ${CURDIR}
    link_executables $INSTALL_BASE
fi

###############
# RUN
###############

if [[ -z $TEST ]]; then
    echo "NO TEST JUST BUILD"
    exit 0
fi

CMD=${INSTALL_BASE}/bin/${TEST}

set_ompi_flags
set_logs

echo $THEDATE > $RUN_LOG
echo "init_host,dest_host,bw" > $RUN_RSLT

for hi in $(scontrol show hostnames $SLURM_NODELIST); do
    echo "${TEST^^} - $hi"
    si=${SECONDS}
    for h in $(scontrol show hostnames $SLURM_NODELIST); do
        if [[ $h == $hi ]]; then continue; fi
        echo "$hi,$h"
        echo "mpirun ${RUN_ARGS} -host ${hi},${h} ${CMD} ${CMD_ARGS}" &>> $RUN_LOG
        mpirun ${RUN_ARGS} -host "${hi},${h}" ${CMD} ${CMD_ARGS} &> $RUN_TMP
        bw_num=$(awk '/262144/ {print $NF}' $RUN_TMP)
        cat $RUN_TMP >> $RUN_LOG
        if [[ -z $bw_num ]]; then
            echo "TEST $hi,$h FAILED!!!:"
            echo "CANCELLING TEST"
            cat $RUN_TMP
            exit 1
        fi
        echo "$hi,$h,$bw_num" >> $RUN_RSLT
        save_full_rslt $RUN_TMP $RUN_RSLT_FULL "Size,${hi}-${h}"
    done
    sf=$(( SECONDS-si ))
    echo "$hi took $sf seconds."
done