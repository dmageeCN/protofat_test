## Advanced Routing Wiki

Run `get_src.sh` first to get the tests in your local repo.

### INTRO

#### FGAR

#### SDR

#### EDC

### Procedure

* On the FM NODE: 
  * Take the desired file from `fmconfigs` and `/etc/opa-fm/opafm.xml` with it. To restore defaults, replace `/etc/opa-fm/opafm.xml` with `fmconfigs/default-opafm.xml`.
  * Restart the opafm service `systemctl restart opafm`. Check it's running with `status`.

### FMCONFIGS FILES:

Edit the `/etc/opafm/opafm.xml` file on the FM node:

#### COMMON

* LINES 2484-2490:
  * Edit `<Port>` = 2
  * Edit `<LogFile>` = `/var/log/{algo}_protofat_fm_log`
* LINES 1015-1115
  * Edit `<RoutingAlgorithm>` = fattree
  * Edit: `<TierCount>` = 0

#### FGAR

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

#### SDR

Static Dispersive Routing.

SDR RUNS under the FGAR xml configuration. To use SDR set the FI_OPX variables listed above except:

``` bash
### SET THIS FOR SDR
export FI_OPX_ROUTE_CONTROL='0:0:0:0:0:0'
```

Static Dispersive Routing will be available once the entropy bit is enabled in OPX.

#### EDC

### TESTS

#### GPCNET

#### UNIBAND

#### NAMD

### FABRIC THROTTLING

#### BOUNCING LINKS

#### OVERSUBSCRIPTION