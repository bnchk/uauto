# AUTOBOX - Automated Ubuntu patch rebooting<br>
Manages reboots around updates/patching for simple box running one service/job, as a wrapper for unattended-updates.<br>
If Ubuntu can install patches without requiring an update it is left to do so.  Tested on Ubuntu 22.04.<br>
Only for situations where defaults accepted for everything, as automation requires this to prevent prompts popping up.<br><br>
Requires needsupdate + unattended-updates packages.  These are not always installed by default so may need to be added.<br>
Unattended updates has to be installed+running and this script will maintain the reboots/any unapplied patches.<br><br>
Push message account has to be setup and you have 2x API keys (user+app) as per [pushover account](https://github.com/bnchk/UbuntuAutomation/tree/main/push-message-setup).<br>
Message priority can be set in the script, defaults to silent messages unless rebooting.<br><br>
This job is run as a user with sudo access, with script whitelisted for non password prompting so it can be fully automated.<br><br>
OpenSSH server and tailscale are updated immediately if patch exists.<br>
GRUB updates will cause halting of this script, and request sent to apply manually.<br><br>
Unapplied update counts are split 4ways into Distribution-Standard+Security, and Standard-Standard+Security.<br>
Counts go up/down if Ubuntu is able to apply them without reboot being required (depends on schedules).<br><br>
The box will be rebooted (and also apply any low priority patches/ones left by unattended-updates) if:
* unattended updates or this script have applied patch(s) which require reboot for full installation.
* days since last rebooted variable limit is reached (variable you set, default is 21days).<br><br>

# CONFIGURATION
Security note - as per standard practice, ensure only the sudo user running the task can edit the script.<br>
This eliminates privilege escalation security risk where lower access user adds line in automated script<br>
to give themselves higher access next time it runs.<br><br>
One method to compartmentalise security is 3 users:
* sudo user - schedules scripts like this one/sudo tasks
* service user - no sudo, but runs the job the box is there for
* access user - no sudo, ssh in via this user
<br>
This example uses /opt/my_scripts/autobox/autobox.sh, and a secrets.txt file in the same folder.<br>
If you modify the location, also change the scripts variable for secrets file location.<br>

## PACKAGES ADDITION:
These may already be installed, but if not:
```bash
sudo apt update && sudo apt upgrade && \
sudo apt install -y needrestart unattended-upgrades
```
If unattended-upgrades not running:
```bash
sudo dpkg-reconfigure --priority=low unattended-upgrades
```

## SCRIPT STORAGE:
This example sets restrictive permissions (privesc prevention).  Open editor on script file:
```bash
sudo mkdir -p /opt/my_scripts/autobox && \
sudo touch /opt/my_scripts/autobox/autobox.sh && \
sudo chmod 700 /opt/my_scripts/autobox/autobox.sh && \
sudo nano /opt/my_scripts/autobox/autobox.sh
```
Copy the raw autobox.sh script, paste into editor plus save it.<br>
Set variables in code:
* Edit the max_days_without_reboot variable (default set to 21)
* Run beta_code = y/n - yes will update to openssh_server

## SECRETS FILE
Contains the 2 api keys for push messages, plus service to stop (if any).<br>
Open editor on script file:
```bash
sudo touch /opt/my_scripts/autobox/secrets.txt && \
sudo chmod 700 /opt/my_scripts/autobox/secrets.txt && \
sudo nano /opt/my_scripts/autobox/secrets.txt
```
<br>Copy paste into secrets file, plus change API tokens + service name to suit:
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
The whole script is whitelisted for sudo without password prompt (so automation can run on its own).<br>
This is why security is important.  To whitelist the script:
```bash
sudo visudo
```
Add this line at end replacing youruser with the user scheduling script, plus change path/scriptname if you modified location:<br>
```bash
youruser ALL=(ALL) NOPASSWD: /opt/my_scripts/autobox/autobox.sh
```
Schedule the job using crontab:
```bash
crontab -e
```
Enter a run schedule at end or crontable again changing script name/location if required, eg for 8:30am:<br>
```bash
30 8 * * * sudo /opt/my_scripts/autobox/autobox.sh
```

## SAMPLE MESSAGES
Messages will provide 
* counts of security+standard patches broken into standard and dist groups
* days since last reboot
* whether reboot was required
* send tailscale version information
* etc<br><br>
![sample_message1](./assets/sample_msgs1sml.png) <br>
