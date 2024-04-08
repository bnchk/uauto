# Ubuntu Automation Suite<br>
Intended for simple boxes to run entirely on their own, providing minimal updates - just enough to let you know it is OK, plus any issues/what is done to resolve.  Written for simple setups not running prometheus/grafana and wanting machine to ping via push message if there was anything that needed attention.<br>
<br>
## Scripts cover:<br>
* logon notifications<br>
* patching<br>
* monitoring<br>
* node/relay automation (Cardano projects Iagon+Encoins+WM)<br>
* push message communication<br>
<br>

## Messages are:<br>
* once a day summary in stable status<br>
* hourly of any issue (first message within a few minutes), and across what updates/reboots are being performed and why<br>
* updates to node/relay binaries<br>
* instant warning of user connections being made<br>
<br><br>
# REQUIRED - pushover.net account:<br>
## Step1:  Create pushover.net account +  get user api-key<br>
* $5 per device class perpetual licence (or can use trial period to test)<br>
* This will give you a user api key<br>
* Am not affiliated in any way, they simply looked good.  There are other choices.<br><br>
## Step2:  Create application per sub-use (eg monitoring/updates/etc)<br>
* Get a secondary api-keys for free for each sub-grouping you will use<br>
* Scripts ALL use both a user key + application key<br>
* If you want only one sub-grouping (no subgrouping) just create the one for use by all scripts<br>
* Allow grouping of notifications by application (eg all ssh logons, or just ssh logons for certain machines)<br>
* Can add thumbnail for each application - eg binoculars for monitoring etc (but is not compulsory)<br>
<br>
<br>
<br>
Coded for self but any feedback/suggestions really appreciated :-)
