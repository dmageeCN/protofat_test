#!/bin/bash

setvar() {
    while [[ $# -gt 0 ]]; do
        export $1
        shift
    done
}

mkcd () {
    set -e
    echo $1
    mkdir -p "${1}" && cd "${1}"
    set +e
}

export CFLAGS='-w'
export CXXFLAGS='-w'

export CURDIR=$(realpath $PWD)
export THEDATE=$(date +'%m-%d_%H-%M')

export FMNODE=icx013

## FIND THIS DIRECTORY
if [[ -z $THISDIR ]]; then
    THISFILE=${BASH_SOURCE[0]}
    : ${THISFILE:=$0}

    export THISDIR=$(dirname $(realpath ${THISFILE}))
fi

## ACTIVATE PYTHON VENV
export VENV_DIR=${THISDIR}/installs/protofat_venv
if [[ -f $VENV_DIR/bin/activate.sh ]]; then
    source $VENV_DIR/bin/activate.sh
fi

universal_opts() {
    : ${COMPILER:=intel}
    : ${MPI:=intel}
    : ${INSTALL_BASE:=${THISDIR}/installs/${NAME}-${COMPILER}_${MPI}}
    : ${BUILD_BASE:=/tmp/build_${NAME}/${COMPILER}_${MPI}}
    : ${SRC_BASE:=${THISDIR}/src}
    : ${FI_PROV:=opx}
    : ${VERBOSE:=false}
    : ${LOGDIR:=${PWD}/${NAME}_protofat_result}
    : ${HFI_ID:=0} ## NUMBER ID OF NIC.
    : ${REBUILD:=false} ## NUMBER ID OF NIC.
    : ${FM_ALGO:=default}
    : ${HFISVC:=1}
    : ${MIXED_NET:=1}
    : ${PROFILE:=false}
    
    export COMPILER MPI INSTALL_BASE BUILD_BASE SRC_BASE 
    export FI_PROV VERBOSE LOGDIR HFI_ID REBUILD FM_ALGO
    export HFISVC MIXED_NET PROFILE
}

cpu_info() {
    export NNUMAS=$(lscpu | awk '/NUMA node\(/ {print $NF}')
    export CORES_PER_SOCKET=$(lscpu | awk '/Core\(/ {print $NF}')
    export NSOCKETS=$(lscpu | awk '/Socket\(/ {print $NF}')
    export TOTAL_CORES=$(( CORES_PER_SOCKET*NSOCKETS ))
    export NUMAS_PER_SOCKET=$(( NNUMAS/NSOCKETS ))
    export NUMA_WIDTH=$(( TOTAL_CORES/NNUMAS ))
}

opx_software() {
    stack_ver=$(cat /etc/opa/version_delta)
    config_string="OFA_OPA_Stack: ${stack_ver}" 
    rpm_ver=$(rpm --queryformat "[%{VERSION}.%{RELEASE}]" -q opa-fm | sed 's/\.[^.]*$//')
    config_string+=" - OPA_FM: ${rpm_ver}"
    rpm_ver=$(rpm --queryformat "[%{VERSION}.%{RELEASE}]" -q opa-fastfabric | sed 's/\.[^.]*$//')
    config_string+=" - OPA_FASTFABRIC: ${rpm_ver}"
    rpm_ver=$(rpm --queryformat "[%{VERSION}.%{RELEASE}]" -q opa-basic-tools | sed 's/\.[^.]*$//')
    config_string+=" - OPA_TOOLS: ${rpm_ver}"
    rpm_ver=$(rpm --queryformat "[%{VERSION}.%{RELEASE}]" -q opa-libopamgt | sed 's/\.[^.]*$//')
    config_string+=" - OPA_MANAGEMENT_SDK: ${rpm_ver}"
    rpm_ver=$(rpm --queryformat "[%{VERSION}.%{RELEASE}]" -q opxs-kernel-updates-devel)
    config_string+=" - OPXS_KERNEL_UPDATES: ${rpm_ver}"
    echo $config_string
}

set_compiler_mpi() {
    if [[ $COMPILER == 'intel' && $MPI == 'intel' ]]; then
        export I_MPI_OFI_LIBRARY_INTERNAL=0
        source /opt/intel/oneapi/setvars.sh
        export CC=mpiicx FC=mpiifort CXX=mpiicpx
        MPI_VER=$(mpirun --version | awk '{print $8; exit}')
        COMPILER_VER=$(icx --version | awk '{print $(NF-1); exit}')
    fi

    if [[ $COMPILER == 'gcc' && $MPI == 'ompi' ]]; then
        if [[ -z $MPI_HOME ]]; then
            mpi_h=/usr/mpi/gcc/openmpi
            if [[ ! (-d $mpi_h) ]]; then
                mpi_h=/usr/mpi/gcc/openmpi-4.1.6-hfi
            fi
            if [[ ! (-d $mpi_h) ]]; then
                echo "!! Can not find OMPI in the usual spot. "
                echo "-- SET MPI_HOME on the CL."
                exit 1
            fi
            export MPI_HOME=$mpi_h
            MPI_VER=$(mpirun --version | awk '{print $NF; exit}')
            COMPILER_VER=$(gcc --version | awk '{print $3; exit}')
        fi
        export PATH=$MPI_HOME/bin:$PATH
        export LD_LIBRARY_PATH=$MPI_HOME/lib:$MPI_HOME/lib64:$LD_LIBRARY_PATH
        export CC=mpicc FC=mpifort CXX=mpicxx
        export COMPILER_VER MPI_VER
    fi

    export CFLAGS='-w'
    export CXXFLAGS='-w'
}

set_mpi_flags() {
    num_nodes=$1
    ppn=$2
    procs=$(( ppn*num_nodes ))
    runargs="-np ${procs} "
    cpu_info
    export FI_PROVIDER=$FI_PROV
    if [[ $FI_PROV == 'opx' ]]; then
        if [[ ! ($MPI == 'intel') ]]; then
            runargs+="--map-by ppr:${ppn}:node --mca pml cm --mca mtl ofi --mca mtl_ofi_provider_include opx "
            if [[ $VERBOSE == "true" ]]; then
                runargs+="--verbose --report-bindings -x FI_LOG_LEVEL=debug -x FI_LOG_SUBSYS=core "
            fi
        else
            runargs+="-ppn ${ppn} "
            export I_MPI_FABRICS=shm:ofi
            if [[ $VERBOSE == "true" ]]; then
                export I_MPI_DEBUG=10
            fi
        fi
        if [[ $HFI_ID == "0,1" ]]; then
        # Intel MPI finds the NIC based on the CPU process pinning.
        # Setting other env vars just gets in the way and causes errors.
            if [[ $MPI == 'intel' ]]; then
                procs_per_numa=$(( ppn/2 ))
                end1=$(( 16+procs_per_numa-1 ))
                end2=$(( 48+procs_per_numa-1 ))
                export I_MPI_PIN_PROCESSOR_LIST="16-${end1},48-${end2}"
            fi
        else
            export NUMA_NODE=$(( (2*HFI_ID)+1 ))
            if [[ $MPI == intel ]]; then
                if [[ $ppn -lt $NUMA_WIDTH ]]; then
                    NUMA_START=$(( NUMA_NODE*NUMA_WIDTH ))
                    NUMA_END=$(( NUMA_START+ppn-1 ))
                    export I_MPI_PIN_PROCESSOR_LIST="${NUMA_START}-${NUMA_END}"
                fi
            else
                runargs+="--bind-to none"
            fi
            export FI_OPX_HFI_SELECT=$HFI_ID
        fi
        export FI_OPX_HFISVC=$HFISVC
        export FI_OPX_MIXED_NETWORK=$MIXED_NET
    fi

    export RUN_ARGS=$runargs
    export PROCS=$procs
}

check_fgar() {
    SWITCH_LID=$(opaextractlids |& awk -F';' '/SW/ {print $NF}' | head -1)
    SWITCH_CONFIG=$(opasmaquery -o swinfo -l "$SWITCH_HASH" | grep -m 1 Adapt | cut -d' ' -f3,15)
    if [[ "$SWITCH_CONFIG" =~ "0" ]]; then
        echo "FGAR IS NOT ACTIVE."
        return 1
    fi
    return 0
}

set_fgar() {
    # ssh $FMNODE "cp /etc/opa-fm/opafm.xml /etc/opa-fm/opafm-default.xml && \
    #     cp ${THISDIR}/fmconfigs/fgar-opafm.xml /etc/opa-fm/opafm.xml && \
    #     systemctl restart opafm"
    if [[ ! $(check_fgar) ]]; then
        return 0
    fi
    export FI_OPX_MIX_ORIG=$FI_OPX_MIXED_NETWORK
    export FI_OPX_TID_ORIG=$FI_OPX_TID_DISABLED
    export FI_OPX_ROUTE_ORIG=$FI_OPX_ROUTE_CONTROL
    export FI_OPX_MIXED_NETWORK=0
    export FI_OPX_TID_DISABLED=1
    route_control='4:4:4:4:4:4'
    if [[ $FM_ALGO == 'sdr' ]]; then
        export route_control='0:0:0:0:0:0'
    fi
    export FI_OPX_ROUTE_CONTROL=$route_control
    echo "${FM_ALGO} config set"
}

unset_fgar() {
    if [[ -f /etc/opa-fm/opafm-default.xml ]]; then
        # ssh $FMNODE "cp /etc/opa-fm/opafm-default.xml /etc/opa-fm/opafm.xml && \
        #     systemctl restart opafm"
        export FI_OPX_MIXED_NETWORK=$FI_OPX_MIX_ORIG
        export FI_OPX_TID_DISABLED=$FI_OPX_TID_ORIG
        export FI_OPX_ROUTE_CONTROL=$FI_OPX_ROUTE_ORIG
    fi
}

detect_algo() {
    SWITCH_LID=$(opaextractlids |& awk -F';' '/SW/ {print $NF}' | head -1)
    SM_QUERY=$(opasmaquery -o sitscvlt -l $SWITCH_LID -m 41)

    # Fat tree will give a sitscvlt where everything maps to VL 15 except for SIT0
    # shortest path will have all SITX set to the same value

    ### SHORTEST PATH: Some SIT0 VLT have 08 on odd cols (1,{2,4,22,24,28,32,36,40,60,64,72,76...}) the others have all 00.

    # 1 ,    76 |   SIT0:
    #           |       SC: 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
    #           |      VLT: 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08 00 08
    #           |   SIT1:
    #           |       SC: 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
    #           |      VLT: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    #           |   SIT2:
    #           |       SC: 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
    #           |      VLT: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00
    #           |   SIT3:
    #           |       SC: 00 01 02 03 04 05 06 07 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22 23 24 25 26 27 28 29 30 31
    #           |      VLT: 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00 00



}

set_logs() {
    TESTID=${1}
    EXTRA_CONFIG=${2}
    if [[ $FM_ALGO == "default" ]]; then detect_algo; fi
    IDENTIFIER="${COMPILER}_${MPI}-${NAME}-${FM_ALGO}-${THEDATE}"
    mkdir -p ${LOGDIR}/${IDENTIFIER}
    export RUN_LOG=${LOGDIR}/${IDENTIFIER}/${TESTID}-run.log
    export RUN_TMP=/tmp/${NAME}_run
    export RUN_RSLT=${LOGDIR}/${IDENTIFIER}/${TESTID}-summary.csv
    export RUN_RSLT_FULL=${LOGDIR}/${IDENTIFIER}/${TESTID}-totaltable.csv
    export SWITCH_COUNTER_OUT=${LOGDIR}/${IDENTIFIER}/${TESTID}-swcnt.csv
    export SWITCH_COUNTER_RAW=${LOGDIR}/${IDENTIFIER}/${TESTID}-swcnt.txt
    export NIC_COUNTER_OUT=${LOGDIR}/${IDENTIFIER}/${TESTID}-niccnt.csv
    if [[ $FM_ALGO == "fgar" || $FM_ALGO == "sdr" ]]; then
        set_fgar
    fi
    echo "$NAME - $THEDATE - $FM_ALGO - $TESTID" |& tee $RUN_LOG
    OPX_INFO=$(opx_software)
    config_string="$NAME: $TEST - COMPILER: $COMPILER - COMPILER_VER: $COMPILER_VER"
    config_string+=" - MPI: $MPI - MPI_VER: $MPI_VER - HFI: $HFI_ID - JOBID: $SLURM_JOB_ID "
    config_string+=" - NODELIST: $SLURM_NODELIST - ${EXTRA_CONFIG} - ${OPX_INFO}"
    echo $config_string |& tee -a $RUN_LOG
    echo "LOGDIR:- ${LOGDIR}/${IDENTIFIER}"

}

node_by_edge() {
    nodes_edges=$(opaextractsellinks |& awk -F';' '/hfi1_0/ {print $4,$NF}' | cut -d ' ' -f 1,3 | tr ' ' ',' | sort -t ',' -k2n)
    edgeq=$(echo "$nodes_edges" | cut -d ',' -f 2 | uniq)
    actualnodes=$(scontrol show hostnames $SLURM_NODELIST)
    exclude_list=""
    for k in $(echo "$nodes_edges" | cut -d ',' -f 1); do
        if [[ ! ($actualnodes =~ $k) ]]; then
            exclude_list+="${k}|"
        fi
    done
    exclude_list+="nonsense"
    nodes_edges_f=$(echo "$nodes_edges "| grep -vE "($exclude_list)")
    EDGEARRAY=(1 1 1)
    EDGECOUNT=(1 1 1)
    for n in $edgeq; do 
        edgenum=$(echo $n | awk -F'-' '{print $NF}')
        edges=$(echo "$nodes_edges_f" | grep $n |  cut -d ',' -f 1)
        edgelist=$(echo $edges | tr ' ' ',')
        EDGEARRAY[$edgenum]=$edgelist
        count="${edgelist//[^,]}"
        EDGECOUNT[$edgenum]=$(( ${#count}+1 ))
    done 
    export EDGEARRAY
    export EDGECOUNT
}

#!/bin/bash

# Associative arrays to store before/after counters and node list
declare -A COUNTERS_BEFORE
declare -A COUNTERS_AFTER
export OPA_NODES

# Main function to capture counters
# Call with nodes to capture "before", call without nodes to capture "after" and return CSV row
read_opainfo() {
    cnt_read=$(mpirun -np 1 -host $1 opainfo | awk '/(Xmit|Recv)/ {print $3,$NF}')
    echo $cnt_read | tr ' ' ','
}

opa_readit() {
	data_item=""
    before_arr=($(echo ${1} | tr ',' '\n'))
    after_arr=($(echo ${2} | tr ',' '\n'))
    for k in $(seq 0 $((${#before_arr[@]} - 1))); do
        val=$(( after_arr[$k] - before_arr[$k] ))
        data_item+=",${val}"
    done
	echo $data_item
}

opa_counter() {
    # If arguments provided, this is the "before" capture
    if [ $# -gt 0 ]; then
        OPA_NODES=$(echo ${1} | tr ',' '\n')
        COUNTERS_BEFORE=()  # Clear previous data
        COUNTERS_AFTER=()

        for node in $OPA_NODES; do
            opa_cnt=$(read_opainfo $node)
            COUNTERS_BEFORE[$node]=$opa_cnt
        done
        export COUNTERS_BEFORE
        return 0
    fi

    
    # No arguments - this is the "after" capture, calculate and return CSV row
    if [ ${#OPA_NODES[@]} -eq 0 ]; then
        echo "Error: No nodes saved from previous call" >&2
        return 1
    fi
    
    # Capture "after" counters
    for node in $OPA_NODES; do
       	opa_cnt=$(read_opainfo $node)
       	COUNTERS_AFTER[$node]=$opa_cnt
    done
    export COUNTERS_AFTER
    
    header="XmitData_0,XmitPkts_0,RecvData_0,RecvPkts_0"
    header_templ=$header
    node1=$(echo "$OPA_NODES" | head -1)
    node1ctr=${COUNTERS_AFTER[$node1]}
    num_data=${#node1ctr[@]}
    num_nics=$(( num_data/4-1 ))
    for k in $(seq 1 $num_nics); do
        header+=",$(echo $header_templ | tr '0' $k)"
    done

    header="Node,${header}"
    data=""

    for node in $OPA_NODES; do
        data_row=$(opa_readit "${COUNTERS_BEFORE[$node]}" "${COUNTERS_AFTER[$node]}")
       	data+="${node}${data_row}\n"
    done

    # Output header and data
    echo "$header"
    echo -e "$data"
}
    
    # Output header and data
    echo "$header"
    echo -e "$data"
}

# Example usage:
#
# # Before benchmark
# opa_counter node1 node2 node3
#
# # Run your benchmark
# mpirun -np 4 -host node1,node2 ./osu_bw
#
# # After benchmark - get CSV output
# opa_counter > results.csv
#
# # Or capture to variable
# csv_output=$(opa_counter)
# echo "$csv_output" >> all_results.csv

# export COUNTER_I
# export COUNTER_F
# opa_counter() {
#     h1=$1
#     h2=$2
#     stage
#     h1_counters=$(mpirun -np 1 -host $h1 opainfo | awk '/(Xmit|Recv)/ {print $NF}')
#     h2_counters=$(mpirun -np 1 -host $h2 opainfo | awk '/(Xmit|Recv)/ {print $NF}')
# }

export NODELIST=$(scontrol show hostnames $SLURM_NODELIST)
export COMMA_NODELIST=$(echo "$NODELIST" | tr '\n' ',' | sed 's/,$//g')
