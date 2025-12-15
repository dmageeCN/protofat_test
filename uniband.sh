#!/bin/bash

export NAME=UNIBAND

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

# SET DEFAULT OPTIONS FOR THIS PARTICULAR TEST
: ${VERBOSE:=false}
: ${PPN:=4}
: ${TESTS:=all}
: ${NNODES:=$SLURM_NNODES}
: ${HISET:=''} # SET NODE TO TEST AGAINST ALL OTHER NODES.

if [[ $TESTS == 'all' ]]; then TESTS='pairwise,edgewise,crosswise'; fi

mkdir -p $LOGDIR

set_compiler_mpi

CMD=IMB-MPI1
CMD_ARGS="Uniband -npmin 9999 -msglog 20:21"

run_fulledge() {
    nodelist=$1
    printonly=$2
    nnodes=$(echo "$nodelist" | awk -F',' '{print NF}')
    if [[ $(( nnodes%2 )) == 1 ]]; then
        nodelist="${nodelist%,*}"
        nnodes=$(( nnodes-1 ))
    fi
    TARGET=$(( nnodes*12 ))

    echo "Uniband $nnodes Nodes  --- TARGET=$TARGET GB/s"

    echo "mpirun -np $((nnodes*ppn)) -ppn $PPN -host ${nodelist} ${CMD} ${CMD_ARGS}"
    if [[ -z $printonly ]]; then
        echo $printonly
        mpirun -np $((nnodes*ppn)) -ppn $PPN -host "${nodelist}" ${CMD} ${CMD_ARGS}
    fi
}

INTEL_VER=2024.1
# IMB_SRC=/opt/intel/${INTEL_VER}/opt/mpi/benchmarks/
# MPI_BIN=/opt/intel/${INTEL_VER}/bin
# export PATH=$PATH:$MPI_BIN
hin=$(hostname)
hi=${hin%%.*}

set_logs "$TESTS"

PITER=30
PSPAN=10
if [[ ! ($TESTS =~ 'pairwise') ]]; then 
    PITER=10
    PSPAN=2
fi
PROFILER=$THISDIR/pmaCountersFromSwitch.sh
PROFILER_FIELDS="Xmit Pkts, Rcv Pkts, Xmit Time Cong, Xmit Wait, Rcv Bubble"
$PROFILER 0 3 $PITER $PSPAN $PROFILER_FIELDS $RUN_COUNTER_OUT $RUN_COUNTER_RAW &

set_mpi_flags $NNODES $PPN
# tail -n27 $HOME/28hosts
: ${HISET:=$NODELIST}
if [[ $TESTS =~ 'pairwise' ]]; then
    set_logs pairwise "PROCS_PER_NODE: $PPN"
    echo FI_OPX_MIXED_NETWORK=${FI_OPX_MIXED_NETWORK}
    echo FI_OPX_TID_DISABLED=${FI_OPX_TID_DISABLED}
    echo FI_OPX_ROUTE_CONTROL=${FI_OPX_ROUTE_CONTROL}
    export nodes=2 ppn=4
    echo "init_host,dest_host,bw" > $RUN_RSLT
    for hi in $HISET; do
        echo "Uniband Pairwise - $hi"
        si=${SECONDS}
        for h in $NODELIST; do
            if [[ $h == $hi ]]; then continue; fi
            echo "$hi,$h"
            echo "mpirun -np 8 -ppn $PPN -host ${hi},${h} ${CMD} ${CMD_ARGS}" &> $RUN_TMP 
            mpirun -np 8 -ppn $PPN -host "${hi},${h}" ${CMD} ${CMD_ARGS} &>> $RUN_TMP
            # grep "^      2097152" $RUN_TMP | sed "s/^/$h /g"
            bw_num=$(awk '/2097152   / {print $3}' $RUN_TMP)
            echo "$hi,$h,$bw_num" >> $RUN_RSLT
            cat $RUN_TMP >> $RUN_LOG
        done
        sf=$(( SECONDS-si ))
        echo "$hi took $sf seconds."
    done
fi

node_by_edge
if [[ $TESTS =~ 'edgewise' ]]; then
    si=${SECONDS}
    set_logs edgewise "PROCS_PER_NODE: $PPN"
    for k in $(seq $(( ${#EDGEARRAY[@]}-1 ))); do
        nodelist=${EDGEARRAY[$k]}

        if [[ -n $nodelist ]]; then
            run_fulledge $nodelist |& tee -a $RUN_LOG
        else
            break
        fi

    done
    sf=$(( SECONDS-si ))
    echo "EDGEWISE took $sf seconds."
fi

if [[ $TESTS =~ 'crosswise' ]]; then
    si=${SECONDS}
    set_logs crosswise "PROCS_PER_NODE: $PPN"
    for idx in $(seq $(( ${#EDGEARRAY[@]}-2 ))); do
        idx2=$(($idx+1))
        echo "Uniband crosswise on edges $idx $idx2" |& tee -a $RUN_LOG
        ec1=${EDGECOUNT[$idx]}
        ec2=${EDGECOUNT[$idx2]}
        edgemin=$((ec1 < ec2 ? ec1 : ec2))
        nodes1=$(echo "${EDGEARRAY[$idx]}" | cut -d',' -f1-${edgemin})
        nodes2=$(echo "${EDGEARRAY[$idx2]}" | cut -d',' -f1-${edgemin})
        nodelist="${nodes1},${nodes2}"
        echo "Min edge nodes: $edgemin" |& tee -a $RUN_LOG
        echo "Edge $idx nnodes: $ec1" |& tee -a $RUN_LOG
        echo "Orig EDGE $idx: ${EDGEARRAY[$idx]}" |& tee -a $RUN_LOG
        echo "Cut  EDGE $idx: $nodes1" |& tee -a $RUN_LOG
        echo "-----" |& tee -a $RUN_LOG
        echo "Edge $idx2 nnodes: $ec2" |& tee -a $RUN_LOG
        echo "Orig EDGE $idx2: ${EDGEARRAY[$idx2]}" |& tee -a $RUN_LOG
        echo "Cut  EDGE $idx2: $nodes2" |& tee -a $RUN_LOG
        run_fulledge $nodelist |& tee -a $RUN_LOG
    done
    sf=$(( SECONDS-si ))
    echo "CROSSWISE took $sf seconds."
fi
# $HOME/jp_scripts/get-my-intel-bios.sh
