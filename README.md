## Advanced Routing Wiki

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

### FGAR

* LINES 1814-1817:
  * Edit `<Enable>` = 1
  * Edit `<FineGrained>` = 1

#### SDR

#### EDC

### TESTS

#### GPCNET

#### UNIBAND

#### NAMD

### FABRIC THROTTLING

#### BOUNCING LINKS

#### OVERSUBSCRIPTION