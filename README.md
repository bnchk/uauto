# Ubuntu Automation - simple scripts<br>
Very much a use at your own risk.  Intention is to learn how to automate basic boxes to run entirely on their own, then work on to more complex ones.
Started with Cardano Iagon CLI box automation, then Encoins relay as practice with aim being to see if it is possible for World Mobile Earth node.
The intent is that an Ubuntu box can run on its own providing minimal updates via push message - just enough to let you know it is OK, plus any issues/what is done to resolve.
Am not sure at this point how it would work with prometheus/grafana based setups, but suspect this would not be necessary.<br>
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
Coded for self as a learning lesson, but any feedback/suggestions really appreciated :-)
