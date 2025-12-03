#!/bin/bash

restart_complete() {
    for node in $(scontrol show hostnames $SLURM_NODELIST); do
        linkup=0
        while [[ linkup -ne 2 ]]; do
            linkup=$(opaextractlids 2> /dev/null | grep -c $node)
        done
        echo "$node has two lids"
    done
}

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