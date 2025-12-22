# Advanced Routing Wiki

Run `get_src.sh` first to get the tests in your local repo, and set up the python venv.

## INTRO

### OPTIONS

Each `{test}.sh` script takes command line options of the form `KEY=value`. The options common to all (or most tests can be found in utils.sh:universal_opts). 

This is convenient because it's not limited to the explicit options. You can add any environment variable to the run/build time environment by declaring it as a command line option.

A test activates the options with these lines:

``` bash
# SET COMMAND LINE OPTIONS
setvar "$@"

# SET DEFAULT OPTIONS THAT APPLY FOR EVERY TEST
universal_opts

# SET DEFAULT OPTIONS FOR THIS PARTICULAR TEST
: ${TESTS:=all}
...
```

Setvar exports the CL argsto the environment. Then universal_opts applies common defaults to any explicit CL options that aren't declared. Then the script applies its own default values to explicit CL options that are unique to the test.

The common options are:

| Variable | Default | Type | Purpose / Notes |
|---|---:|---|---|
| `COMPILER` | `intel` | string | Which compiler toolchain to use (e.g., `intel`, `gcc`). |
| `MPI` | `intel` | string | MPI implementation (e.g., `intel`, `ompi`). |
| `INSTALL_BASE` | `${THISDIR}/installs/${NAME}-${COMPILER}_${MPI}` | path | Where compiled binaries are installed. |
| `BUILD_BASE` | `/tmp/build_${NAME}/${COMPILER}_${MPI}` | path | Temporary build directory. |
| `SRC_BASE` | `${THISDIR}/src` | path | Local source checkout root. |
| `FI_PROV` | `opx` | string | Fabric provider (used by MPI / OFI config). |
| `VERBOSE` | `false` | boolean | Enable verbose output/debugging. |
| `LOGDIR` | `${PWD}/${NAME}_protofat_result` | path | Base directory for test logs and outputs. |
| `HFI_ID` | `0` | string/number | NIC identifier(s) (e.g., `0`, `0,1`) for bindings. |
| `REBUILD` | `false` | boolean | Force rebuild behaviour (script-specific). |
| `FM_ALGO` | `default` | string | Fabric manager algorithm (e.g., `default`, `fgar`, `sdr`). |
| `HFISVC` | `1` | integer | HFISVC value exported to `FI_OPX_HFISVC`. |
| `MIXED_NET` | `1` | integer | Mixed-network flag exported to `FI_OPX_MIXED_NETWORK`. |
| `PROFILE` | `false` | boolean | Turn profiling on/off (affects scripts that read this). |

**EXAMPLES**
Rebuild and run gpcnet with GCC + Open MPI on hfi1_1:

``` bash
./gpcnet.sh COMPILER=gcc MPI=ompi REBUILD=true HFI_ID=1
```

Enable verbose and profiling for dual rail Uniband:
``` bash
./uniband.sh VERBOSE=true PROFILE=true HFI_ID=0,1
```

* These variables are read by functions such as `set_compiler_mpi()`, `set_mpi_flags()`, `set_logs()` and `set_fgar()` in `util.sh`.

### FGAR

### SDR

### EDC

## Procedure

### SWITCHING FM CONFIGS

* On the FM NODE as root:
  * Take the desired file from `fmconfigs` and `/etc/opa-fm/opafm.xml` with it. To restore defaults, replace `/etc/opa-fm/opafm.xml` with `fmconfigs/default-opafm.xml`.
  * Restart the opafm service `systemctl restart opafm`. Check it's running with `status`.


### SWITCHING TO FGAR

### UPDATING FIRMWARE

The firmware can be found in `/nfs/shares/stlbuilds/System_Test/` on the ptc cluster. Grab the JKR_{version} (NIC) and MYR_{version} (Switch) in this directory. Grab the `FW_UPDATE_{closest version}/X86_64_RHEL9_5/*.tgz`. Tar up the JKR and MYR folders in your home dir and copy them down, then up to the benchmark cluster, I use (`/bfs3/dmagee/hw/protofat_SWFW`).

#### NICs

#### SWITCHES

### UPDATING SOFTWARE

## FMCONFIGS FILES (opafm.xml)

- FM XML files under `fmconfigs/` and `/etc/opafm/opafm.xml` control routing:
  - See the `set_fgar` implementation in [util.sh](util.sh) for the FGAR/SDR environment variables:
    - FI_OPX_MIXED_NETWORK, FI_OPX_TID_DISABLED, FI_OPX_ROUTE_CONTROL

Edit the `/etc/opafm/opafm.xml` file on the FM node:

### COMMON

* LINES 671-683: `<Common><VirtualFabrics><VirtualFabric> (Name: Default)`
  * Edit: `<QOS>` = 1
  * Add: `<BaseSL>` = 0
  * Add: `<MulticastSL>` = 1
* LINES 1015-1115: `<Common><Sm>`
  * Edit `<RoutingAlgorithm>` = fattree
  * Edit: `<TierCount>` = 0
* LINES 1652-1655 `<Common><Sm><HFILinkPolicy>`
  * Edit ` <PortSubdivisionPolicy><Enable>` = 1
* LINES 2484-2490: `<Fm><Shared>`
  * Edit `<Port>` = 2
  * Edit `<LogFile>` = `/var/log/{algo}_protofat_fm_log`

### FGAR

Fine Grained Adaptive Routing

* LINES 1814-1817:
  * Edit `<Enable>` = 1
  * Edit `<FineGrained>` = 1

Set the environment variables (see the `set_fgar` function in `util.sh`):

``` bash
  export FI_OPX_MIXED_NETWORK=0
  export FI_OPX_TID_DISABLED=1
  export FI_OPX_ROUTE_CONTROL='4:4:4:4:4:4'
```

Static Dispersive Routing.

SDR RUNS under the FGAR xml configuration. To use SDR set the FI_OPX variables listed above except:

``` bash
### SET THIS FOR SDR
export FI_OPX_ROUTE_CONTROL='0:0:0:0:0:0'
```

### EDC

## TESTS

### GPCNET

### UNIBAND

### NAMD

## FABRIC THROTTLING

### BOUNCING LINKS

### OVERSUBSCRIPTION

## TOOLS

### PROFILE

Turn profiling on with the PROFILE option `(true|false) default: false` on the command line.

#### pmaCountersFromSwitch

Envisioned Usage:
Call islCounterCollection as a background process with the following format:
islCounterCollection "data_vl_start" "data_vl_end" "iterations" "time_between_queries" "selected_attributes" "output_file" "raw_output_file"
Where the raw_output_file is optional. For example:
islCounterCollection 0 3 10 10 "Xmit Pkts, Rcv Pkts, Xmit Time Cong, Xmit Wait, Rcv Bubble" pmaOut.csv rawOut.txt
This will collect Xmit Pkts, Rcv Pkts, Xmit Time Cong, Xmit Wait, and Rcv Bubble counters for VLs 0-3, VL 15, and overall for the port for 10 iterations, with 10 seconds between each iteration, and output the processed data to pmaOut.csv and raw query outputs to rawOut.txt