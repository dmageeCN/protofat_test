#!/bin/bash

# Configuration
LOG_FILE="/var/log/fmdaemon_service.log"
SLEEP_TIME=5

# Function to write a timestamped log entry
log_message() {
    local message="$1"
    
    # Write to the dedicated log file
    echo "$(date +'%Y-%m-%d %H:%M:%S') [INFO] $message" >> "$LOG_FILE"
    
    # Also echo to stdout, which systemd captures for 'journalctl'
    echo "SERVICE OUTPUT: $message"
}

# --- Main Logic ---

log_message "FM DAEMON starting up $(hostname) ..."

# Use a while true loop to keep the script running indefinitely
# The 'trap' command ensures a clean exit when systemd sends SIGTERM (shutdown signal)
trap "log_message 'FM DAEMON received SIGTERM. Exiting.'; exit 0" SIGTERM

get_parition_user() {
    localuname='null'
    if systemctl is-active sssd &> /dev/null; then 
        localuname=$(echo "$1" | awk '{print $4}')
    else
        localuid=$(echo "$1" | awk '{print $4}')
        localuname=$(ls -la /home | awk "/$localuid/ {print \$NF}")
    fi
    ### Get's the job id of the 
    if [[ -d /home/${localuname} ]]; then
        echo $localuname
    else
        echo USER_NOT_FOUND
    fi
}

set_new_opafm() {
    new_fmxml=${1}
    cp -f $new_fmxml /etc/opa-fm/opafm.xml
}

restart_opafm() {
    SIGNAL_FILE="$1"
    systemctl restart opafm
    echo "0" > $SIGNAL_FILE
}

while true; do
    
    # --- Task: Check disk usage ---
    # DISK_USAGE=$(df -h / | tail -n 1 | awk '{print $5}')
    # log_message "Current root disk usage: $DISK_USAGE"
    sqpart=$(squeue -p icelake -t R,CG --noheader)
    njobs=$(echo "$sqpart" | wc -l)

    if [[ $njobs -eq 1 ]]; then
        slurmuser=$(get_partition_user "$sqpart")
        if [[ $slurmuser == "USER_NOT_FOUND" ]]; then
            message="FM DAEMON TRIGGERED BY USER_NOT_FOUND- "
            message+="Cannot reset opafm service. Skipping."
            log_message "$message"
        else
            OPA_RESET_DIR="/home/${slurmuser}/.restart_FM"
            OPA_RESET_SIGNAL="${OPA_RESET_DIR}/restart_file"
            if [[ (-f $OPA_RESET_SIGNAL) ]]; then
                signal=$(cat $OPA_RESET_SIGNAL)
                if [[ $signal -eq 1 ]]; then
                    set_new_opafm $OPA_RESET_DIR/opafm_replace.xml
                elif [[ $signal -eq 8 ]]; then
                    set_new_opafm /etc/opa-fm/opafm-default.xml
                fi
                restart_opafm $OPA_RESET_SIGNAL
            fi
        fi

    fi
    
    # --- Task: Sleep for the defined interval ---
    sleep $SLEEP_TIME
done