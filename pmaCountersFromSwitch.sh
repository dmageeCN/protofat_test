#!/bin/bash

declare -A isl_list
declare -A sw_lids
declare -A query_out
switches=""
iterations=0
opa_fabric_switches() {
    switches=$(opareport -q | grep "SW" | awk '{print $1}' | tr '\n' ' ')
    for switch in $switches; do
        isl_list[$switch]=$(opareport -q -o islinks | grep "$switch" | awk '{print $3}' | tr '\n' ' ')
        sw_lids[$switch]=$(opareport -q -o lids | grep "$switch" | awk '{print $1}')
    done
}

perform_queries() {
    opa_fabric_switches
    for switch in $switches; do
        portmask=0
        for isl in ${isl_list[$switch]}; do
            # Use "${switch}_${isl}" as the key for the associative array
            portmask=$(( 1 << isl ))
            portmask_pf=$(printf 0x%X $portmask)
	        query_out["${switch}_${isl}_${iterations}"]="$(opapmaquery -o getdatacounters -n $portmask_pf -w 0xF -l ${sw_lids[$switch]})"
        done
    done
    iterations=$((iterations + 1))
}

## The processing step is yet to come.
data_to_save=""
data_processing() {
    perform_queries
    declare -A processed_data
    for key in "${!query_out[@]}"; do
        data=""
        processed_data["${key}_${vl}"]="$data"
    done
    echo "PROCESSED: ${processed_data[@]}"
}

