#!/bin/bash

# Script for collecting PMA counters from OPA fabric switches
# VL Number Usage:
# - "overall": Gets data before the first VL Number section
# - "0", "1", "2", "3": Gets data for specific VL Number
# - omit parameter: Gets data from entire output (original behavior)

declare -A isl_list
declare -A sw_lids
declare -A query_out
declare -A node_desc
switches=""
iterations=0
vl_mask=0
opa_fabric_switches() {
    opareport_out="$(opareport -q)"
    switches="$(grep "SW" <<< "$opareport_out" | awk '{print $1}' | tr '\n' ' ')"
    isl_list="$(opareport -q -o islinks)"
    lid_list="$(opareport -q -o lids)"
    for switch in $switches; do
        isl_list[$switch]=$(grep "$switch" <<< "$isl_list" | awk '{print $3}' | tr '\n' ' ')
        sw_lids[$switch]=$(grep "$switch" <<< "$lid_list" | awk '{print $1}')
        node_desc[$switch]="$(grep "SW" <<< "$opareport_out" | grep "$switch" | awk -F "SW" '{print $2}')"
    done
}

create_vl_mask() {
    data_vl_start="$1"
    data_vl_end="$2"
    vl_mask=$(( 1 << 15 ))
    for (( vl=data_vl_start; vl<=data_vl_end; vl++ )); do
        vl_mask=$(( vl_mask | (1 << vl) ))
    done
    vl_mask=$(printf 0x%X $vl_mask)
}

perform_queries() {
    for switch in $switches; do
        portmask=0
        for isl in ${isl_list[$switch]}; do
            # Use "${switch}_${isl}" as the key for the associative array
            portmask=$(( 1 << isl ))
            portmask_pf=$(printf 0x%X $portmask)
	        query_out["${switch}_${isl}_${iterations}"]="$(opapmaquery -o getdatacounters -n $portmask_pf -w $vl_mask -l ${sw_lids[$switch]})"
        done
    done
    iterations=$((iterations + 1))
}

# Function to extract specific attributes from query output
# Usage: extract_attributes "query_data" "attr1,attr2,attr3" [vl_number]
# Returns: comma-delimited values for the requested attributes
# vl_number: "overall" for data before first VL, or specific VL number (0,1,2,3...)
extract_attributes() {
    local query_data="$1"
    local attributes="$2"
    local vl_number="$3"
    local result=""
    local first=true
    local filtered_data=""
    
    # Filter data based on VL number
    if [[ -n "$vl_number" ]]; then
        if [[ "$vl_number" == "overall" ]]; then
            # Get data before the first "VL Number"
            filtered_data=$(echo "$query_data" | awk '/VL Number/ {exit} {print}')
        else
            # Get data for specific VL number
            filtered_data=$(echo "$query_data" | awk -v vl="$vl_number" '
                /VL Number/ {
                    if ($3 == vl) {
                        in_vl = 1
                        next
                    } else if (in_vl) {
                        exit
                    } else {
                        in_vl = 0
                        next
                    }
                }
                in_vl {print}
            ')
        fi
    else
        # Use all data if no VL specified
        filtered_data="$query_data"
    fi
    
    # Convert attributes string to array
    IFS=',' read -ra attr_array <<< "$attributes"
    
    for attr in "${attr_array[@]}"; do
        # Trim whitespace from attribute name
        attr=$(echo "$attr" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')
        
        # Extract value for this attribute from filtered data
        # Look for lines that match the attribute pattern and extract the numeric value
        local value=$(echo "$filtered_data" | grep -E "^[[:space:]]*${attr}[[:space:]]*" | head -1 | awk '{
            # Find the first number in the line (could be MB, Flits, or raw number)
            for(i=1; i<=NF; i++) {
                if($i ~ /^[0-9]+$/) {
                    print $i
                    break
                }
            }
        }')
        
        # If no value found, set to 0
        if [[ -z "$value" ]]; then
            value="0"
        fi
        
        # Add to result with comma separator
        if [[ "$first" == true ]]; then
            result="$value"
            first=false
        else
            result="${result},${value}"
        fi
    done
    
    echo "$result"
}

# Function to get attributes for a specific switch and port
# Usage: get_port_attributes "switch_name" "port_number" "iteration" "attr1,attr2,attr3" [vl_number]
get_port_attributes() {
    local switch="$1"
    local port="$2" 
    local iteration="$3"
    local attributes="$4"
    local vl_number="$5"
    
    local key="${switch}_${port}_${iteration}"
    local query_data="${query_out[$key]}"
    
    if [[ -z "$query_data" ]]; then
        echo "No data found for ${switch} port ${port} iteration ${iteration}"
        return 1
    fi
    
    extract_attributes "$query_data" "$attributes" "$vl_number"
}

# Process the queries and output the data into a csv format
# Usage: data_processing "data_vl_start" "data_vl_end" "selected_attributes" "output_file"
data_processing() {
    data_vl_start="$1"
    data_vl_end="$2"
    selected_attributes="$3"
    output_file="$4"
    echo "GUID,Description,Port,Iteration,VL,${selected_attributes}" > "$output_file"
    for i in $(seq 0 $((iterations - 1))); do
        for switch in $switches; do
            for port in ${isl_list[$switch]}; do
                # Overall port data (before VL breakdowns)
                local overall_values=$(get_port_attributes "$switch" "$port" "$i" "$selected_attributes" "overall")
                echo "$switch,${node_desc[$switch]},$port,$i,Overall,$overall_values" >> "$output_file"

                # Data for each VL in the specified range
                for vl in $(seq $data_vl_start $data_vl_end); do
                    local vl_values=$(get_port_attributes "$switch" "$port" "$i" "$selected_attributes" "$vl")
                    echo "$switch,${node_desc[$switch]},$port,$i,$vl,$vl_values" >> "$output_file"
                done

                local vl15_values=$(get_port_attributes "$switch" "$port" "$i" "$selected_attributes" "15")
                echo "$switch,${node_desc[$switch]},$port,$i,15,$vl15_values" >> "$output_file"
            done
        done
    done
}

initialization() {
    create_vl_mask "$1" "$2"
    opa_fabric_switches
    for switch in $switches; do
        portmask=0
        for isl in ${isl_list[$switch]}; do
            portmask=$(( portmask | (1 << isl) ))
        done
        opapmaquery -o clearportstatus -n $(printf 0x%X $portmask) -l ${sw_lids[$switch]} > /dev/null 2>&1
    done
}

# Usage: islCounterCollection "data_vl_start" "data_vl_end" "iterations" "time_between_queries" "selected_attributes" "output_file" "raw_output_file"
# example call: islCounterCollection 0 3 10 10 "Xmit Pkts, Rcv Pkts, Xmit Time Cong, Xmit Wait, Rcv Bubble" pmaOut.csv rawOut.txt
# This will collect Xmit Pkts, Rcv Pkts, Xmit Time Cong, Xmit Wait, and Rcv Bubble counters for VLs 0-3, VL 15, and overall for the port
# for 10 iterations, with 10 seconds between each iteration, and output the processed data to pmaOut.csv and raw query outputs to rawOut.txt
# Note: FM must be running for initialization to work due to opareport usage, opapmaquery can work without FM
islCounterCollection() {
    initialization "$1" "$2"
    for i in $(seq 1 "$3"); do
        perform_queries
        sleep "$4"
    done
    data_processing "$1" "$2" "$5" "$6"
    if [[ -n "$7" ]]; then
        echo "Raw query outputs" > "$7"
        for switch in $switches; do
            for port in ${isl_list[$switch]}; do
                for iter in $(seq 0 $((iterations - 1))); do
                    key="${switch}_${port}_${iter}"
                    echo "===== Switch: $switch Port: $port Iteration: $iter =====" >> "$7"
                    echo "${query_out[$key]}" >> "$7"
                    echo "" >> "$7"
                done
            done
        done
    fi
}

# islCounterCollection 0 3 10 10 "Xmit Pkts, Rcv Pkts, Xmit Time Cong, Xmit Wait, Rcv Bubble" pmaOut.csv rawOut.txt

islCounterCollection "$1" "$2" "$3" "$4" "$5" "$6" "$7"