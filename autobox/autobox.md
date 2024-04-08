# AUTOBOX GUIDE<br>
Manage updates/patching for simple box running one service/job, and its reboot schedule.<br>
This job is run as a user with sudo access, but script is whitelisted for non password prompting so it can be fully automated.
Basic management is done via unattended updates package, which generally patches once a day and usually does not require a reboot.
When a reboot is required, it doesn't inform you and keeps on patching.  
This script is a wrapper to look after the rest. Is configurable as to triggers initiating patching and reboots.
Communication is via push messages (pushover.net)
<br>
<br>
# CONFIGURATION
==>> IMPORTANT - only the sudo user running the task can edit the script  <<==<br><br>
This eliminates security risk of privilege escalation.<br> 
Privesc is when someone else on the machine (with permission or not) can edit automated script running with elevated access because...they simply edit the script adding command to give their that access next scheduled run.<br>
<br>
This example uses /opt/my_scripts/autobox/autobox.sh, and a secrets.txt file in the same folder - modify as required.<br>
<br>
## SCRIPT STORAGE (securely):
<code>sudo mkdir -p /opt/my_scripts/autobox && \
sudo touch /opt/my_scripts/autobox/autobox.sh && \
sudo chmod 700 /opt/my_scripts/autobox/autobox.sh</code><br>
edit script and copy script into it

## SECRETS FILE
sudo touch /opt/my_scripts/autobox/secrets.txt && \
sudo chmod 700 /opt/my_scripts/autobox/secrets.txt
edit /opt/my_scripts/autobox/secrets.txt and paste in:
usrtoken="userkeyuserkeyuserkeyuserkeyzz"   #user
apitoken="apikeyapikeyapikeyapikeyapikey"   #application key
service="whateverit.service"                #optional service that is to be stopped

## SYSTEM CONFIGURATION 
To prevent the DOS style popups asking about what processes you want restarted or what to do with outdated daemons - force defaults and no prompting.
# - To reboot without DOS style pop-up prompts stopping process needs config changed:
#     sudo vim /etc/needrestart/needrestart.conf
#      - Outdated Daemons warning (UNcomment + change i->a) so #$nrconf{restart} = 'i';  ==> $nrconf{restart} = 'a';
#         - sudo sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
#      - Kernel updates notification - UNcomment this line - $nrconf{kernelhints} = -1;
#         - sudo sed -i "/#\$nrconf{kernelhints} = -1;/s/.*/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf
# - To run sudo without password storage or prompting add whole script to sudoers so everything within it is run with sudo
#      use command:  sudo visudo  # and add line at end:
#                    dog ALL=(ALL) NOPASSWD: /opt/my_scripts/autobox/autobox.sh
# - schedule once a day, run at 8:30am for now, and at reboot:  
#          crontab -e //  30 8 * * * sudo /opt/my_scripts/autobox/autobox.sh
#                         #@reboot sudo /opt/my_scripts/autobox/autobox.sh



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
