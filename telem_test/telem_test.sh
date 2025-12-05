#!/bin/bash

THISFILE=${BASH_SOURCE[0]}
: ${THISFILE:=$0}

THISDIR=$(dirname $(realpath ${THISFILE}))

THEDATE=$(date +'%m-%d_%H-%M')
SWITCH_HASH=$(opaextractlids 2>/dev/null | awk -F';' '/myr-core/ {print $NF}' | head -1)

#BOTH NICS? IDENTIFIER AS ARGUMENT? 
# SAVE NEW OPAFM.XML? WHERE DOES NEW OPAFM GO (HOME FOLDER)?
OPA_RESET_DIR="${HOME}/.restart_FM"
OPA_RESET_SIGNAL="${OPA_RESET_DIR}/restart_file"
EXPERIMENT_FILE="${THISDIR}/experiment.csv"
OPAFM_EXCHANGER="${THISDIR}/make_opafm.py"
TEST_ARCHIVE="${THISDIR}/results"
LOGDIR="${TEST_ARCHIVE}/GPCNET-TELEMTEST-${THEDATE}"
OPAFM_FILES="${LOGDIR}/opafm_files"

TEST="$(dirname ${THISDIR})/gpcnet.sh"
TEST_ARGS="COMPILER=gcc MPI=ompi ALGO=fgar PPN=64 LOGDIR=${TEST_ARCHIVE}/GPCNET-TELEMTEST-${THEDATE}"
RESET_SIGNAL=0

reset_signal() {
    if [[ $RESET_SIGNAL == 1 ]]; then exit 0; fi
    cat "8" > $OPA_RESET_SIGNAL
    RESET_SIGNAL=1
}

check_fgar() {
    SWITCH_CONFIG=$(opasmaquery -o swinfo -l "$SWITCH_HASH" | grep -m 1 Adapt | cut -d' ' -f3,15)
    if [[ "$SWITCH_CONFIG" =~ "0" ]]; then
        echo "FGAR IS NOT ACTIVE. ACTIVATE FGAR AND RETRY."
        exit 1
    fi
}

touch $OPA_RESET_SIGNAL
chmod -R 777 $OPA_RESET_DIR

restart_complete() {
    while [[ $(cat $OPA_RESET_SIGNAL) -ne 0 ]]; do
        sleep 2
    done
    echo "SIGNAL RESET"
    si=$SECONDS
    for node in $(scontrol show hostnames $SLURM_NODELIST); do
        linkup=0
        while [[ linkup -ne 2 ]]; do
            linkup=$(opaextractlids 2> /dev/null | grep -c $node)
            sf=$(( SECONDS-si ))
            if [[ $(( sf % 120 )) -lt 4 ]]; then
                mins=$(( sf/60 ))
                echo "RESTART ACTIVE FOR $mins mins. On node: $node."
            fi
        done
        echo "$node has two lids"
    done
}

check_fgar

trap reset_signal EXIT

count=1
header=$(head -1 $EXPERIMENT_FILE)
for val in $(tail -n +2 $EXPERIMENT_FILE); do
    $OPAFM_EXCHANGER $header $val
    restart_complete
    $TEST "$TEST_ARGS"
    count=$(( count+1 ))
    cp -f ${OPA_RESET_DIR}/opafm_replace.xml ${OPAFM_FILES}/opafm_${count}.xml
done

reset_signal

# I GUESS NOW ALL THAT'S LEFT IS TO MAKE THE DAEMON AND
# PLAY AROUND WITH TELEMETRY BEFORE RUNNING.
# OH AND PUSH THESE CHANGES AND INCORPORATE THE COUNTER SCRIPT.

### THE DAEMON LOOKS FOR A FILE AND READS IT.
# IF THE FILE HAS A 0, IT DOES NOTHING.
# IF THE FILE HAS A 1, IT GRABS AN ADJACENT OPAFM.xml, replaces it and restarts the fabric.
# AFTER IT DECIDES TO RESTART THE FABRIC IT REPLACES THE FILE WITH A 0 FILE.

# Makes a file in the users $HOME/.telem_test folder with the keys to change: opafm_swap.txt

# Calls python script to create new opafm.xml

# Launches sbatch and records job number.

## Python Script has array of values corresponding to xml keys to change for each situation. Puts new opafm.xml in $HOME/.telem_test

## OR Python script is triggered by Daemon that sees opafm_swap.txt. Reads opafm_swap.txt which contains the file of the xml edits and the index of the change to apply.

## Daemon sees opafm_swap.txt and Runs python script to create new opafm.xml

## Daemon restarts opafm service.

## Sbatch waits for opafm restart.

## Runs test

## Records Results

# Waits for job to complete.

# Modifies opafm_swap.txt wth the next index. Launches next job.


## OR DAEMON is triggered by opafm.xml in some $HOME/.opafm_config folder. Swaps that file for etc opafm.xml and restarts the service.

## THIS IS: Create new XML. Launch SBATCH. Wait for it to finish. Save old xml? Create new XML. 