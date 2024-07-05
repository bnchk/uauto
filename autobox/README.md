# AUTOBOX - Automated Ubuntu patching<br>
Manages updates/patching for simple box running one service/job, and its reboot schedule.<br><br>
Only for people who accept defaults for everything, as automation requires this to prevent prompts popping up.<br><br>
Unattended updates has to be installed+running and this script will maintain the reboots/any unapplied patches.<br><br>
Push message account has to be setup and you have 2x API keys (user+app) as per [pushover account](https://github.com/bnchk/UbuntuAutomation/tree/main/push-message-setup).<br><br>
This job is run as a user with sudo access, with script whitelisted for non password prompting so it can be fully automated.<br><br>
In default form a reboot will be triggered if:
* unattended updates applied patch which requires reboot
* openssh server is updated
* tailscale is updated
* days since last rebooted variable limit is reached (you set)<br><br>
# CONFIGURATION
==>> IMPORTANT - only the sudo user running the task can edit the script  <<==<br>
Eliminates privilege escalation security risk where lower access user adds line in automated script<br>
to give themselves higher access next run.<br><br>
This example uses /opt/my_scripts/autobox/autobox.sh, and a secrets.txt file in the same folder - modify as required.<br>
<br>
## SCRIPT STORAGE (securely):
* open editor on script file
```bash
sudo mkdir -p /opt/my_scripts/autobox && \
sudo touch /opt/my_scripts/autobox/autobox.sh && \
sudo chmod 700 /opt/my_scripts/autobox/autobox.sh && \
sudo nano /opt/my_scripts/autobox/autobox.sh
```
* copy raw script and paste into editor plus save it (CNTL-o/NCTL-X)

## SECRETS FILE
* open editor on script file
```bash
sudo touch /opt/my_scripts/autobox/secrets.txt && \
sudo chmod 700 /opt/my_scripts/autobox/secrets.txt && \
sudo nano /opt/my_scripts/autobox/secrets.txt
```
* copy paste into secrets file, plus change API tokens + service name to suit:
```bash
usrtoken="userkeyuserkeyuserkeyuserkeyzz"   #user
apitoken="apikeyapikeyapikeyapikeyapikey"   #application key
service="whateveritis.service"              #optional service that is to be stopped
```

## SYSTEM CONFIGURATION 
There can be no DOS style popups asking for anon-existent human to respond, eg what processes you want restarted/what to do with outdated daemons.  The following will force defaults and no prompting.
* Change outdated Daemons config to force defaults (UNcomment + change i->a so #$nrconf{restart} = 'i';  ==> $nrconf{restart} = 'a'):
```bash
sudo sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
```
* Kernel updates notification (UNcomment this line - $nrconf{kernelhints} = -1;)
```bash
sudo sed -i "/#\$nrconf{kernelhints} = -1;/s/.*/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf
```
* The whole script is whitelisted for sudo without password prompt so automation can run on its own.  This is why security is important.
* use command:  `sudo visudo`
* add this line at end replacing youruser with the user scheduling script, and the path/scriptname if you changed them:<br>
`youruser ALL=(ALL) NOPASSWD: /opt/my_scripts/autobox/autobox.sh`
* schedule the job using crontab:
`crontab -e`
* enter the schedule at end or crontable again changing script name/location if required, eg 8:30am in example:<br>
`30 8 * * * sudo /opt/my_scripts/autobox/autobox.sh`

## SAMPLE MESSAGES
Messages will provide 
* counts of security+standard patches broken into standard and dist groups
* days since last reboot
* whether reboot was required
* send tailscale version information
* etc<br><br>
![sample_message1](./assets/sample_msgs1sml.png) <br>
