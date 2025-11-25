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

if [[ -z $THISDIR ]]; then
    THISFILE=${BASH_SOURCE[0]}
    : ${THISFILE:=$0}

    export THISDIR=$(dirname $(realpath ${THISFILE}))
fi

set_compiler_mpi() {
    if [[ $COMPILER == 'intel' && $MPI == 'intel' ]]; then
        : ${ippn:=$PPN}
        export I_MPI_OFI_LIBRARY_INTERNAL=0
        source /opt/intel/oneapi/setvars.sh
        export CC=mpiicx FC=mpiifort CXX=mpiicpx
        export RUN_ARGS+="-ppn ${ippn} "
    fi

    if [[ $COMPILER == 'gcc' && $MPI == 'ompi' ]]; then
        export MPI_HOME=/usr/mpi/gcc/openmpi-4.1.6-hfi
        export PATH=$MPI_HOME/bin:$PATH
        export LD_LIBRARY_PATH=$MPI_HOME/lib:$MPI_HOME/lib64:$LD_LIBRARY_PATH
        export CC=mpicc FC=mpifort CXX=mpicxx
    fi

    export CFLAGS='-w'
    export CXXFLAGS='-w'
}

set_ompi_flags() {
    runargs=${RUN_ARGS}
    if [[ $FI_PROV == 'opx' ]]; then
        if [[ ! ($MPI == 'intel') ]]; then
            runargs+=" --mca pml cm --mca mtl ofi --mca mtl_ofi_provider_include opx "
        fi
        export FI_PROVIDER=opx # --mca btl_openib_allow_ib 1
    fi

    if [[ $VERBOSE == "true" ]]; then
        runargs+=" --verbose --report-bindings -x FI_LOG_LEVEL=debug -x FI_LOG_SUBSYS=core"
    fi
    export RUN_ARGS=$runargs
}

# THISIS difficult because it'll require sudo.
set_fgar() {
    # ssh $FMNODE "cp /etc/opa-fm/opafm.xml /etc/opa-fm/opafm-default.xml && \
    #     cp ${THISDIR}/fmconfigs/fgar-opafm.xml /etc/opa-fm/opafm.xml && \
    #     systemctl restart opafm"
    export FI_OPX_MIX_ORIG=$FI_OPX_MIXED_NETWORK
    export FI_OPX_TID_ORIG=$FI_OPX_TID_DISABLED
    export FI_OPX_ROUTE_ORIG=$FI_OPX_ROUTE_CONTROL
    export FI_OPX_MIXED_NETWORK=0
    export FI_OPX_TID_DISABLED=1
    route_control='4:4:4:4:4:4'
    if [[ $ALGO == 'sdr' ]]; then
        export route_control='0:0:0:0:0:0'
    fi
    export FI_OPX_ROUTE_CONTROL=$route_control
    echo "${ALGO} config set"
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

set_logs() {
    IDENTIFIER="${COMPILER}_${MPI}-${THEDATE}-${NAME}${1}"
    export RUN_LOG=${LOGDIR}/${IDENTIFIER}-run.log
    export RUN_TMP=/tmp/${NAME}_run
    export RUN_RSLT=${LOGDIR}/${IDENTIFIER}-summary.csv
    export RUN_RSLT_FULL=${LOGDIR}/${IDENTIFIER}-totaltable.csv
    if [[ $ALGO == "fgar" || $ALGO == "sdr" ]]; then
        set_fgar
    fi
}

node_by_edge() {
    nodes_edges=$(opaextractsellinks |& awk -F';' '/hfi1/ {print $4,$NF}' | cut -d ' ' -f 1,3 | tr ' ' ',' | sort -t ',' -k2n)
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