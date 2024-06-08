# LOGIN NOTIFICATIONS<br>
Receive push message whenever there is a connection to Ubuntu.<br>
## SETUP PUSH MESSAGE ACCOUNT + APP
### 1:  pushover.net account<br>
* $5 per device class perpetual licence (or can use trial period to test)<br>
* This will give you a user api key to put in script below<br>
* Not affiliated, liked their free trial+$5 once off<br><br>
### 2:  Create pushover.net application<br>
* Create application under account eg WorldMobile, Iagon, Encoins, logons etc (however you want to group messages by in app)
* Second application api-key is used with above user api key in script below - so 2 keys.<br>
* Optional: add thumbnail image so message embed logo for application - eg:<br><br>
![wm](./assets/world-mobile-logo.png) <br><br>
## NOTIFICATION SCRIPT + LOGON TRIGGERS
### 1: Install curl (if not already)
* `sudo apt-get update && sudo apt-get upgrade`
* `sudo apt install curl`
### 2:  Create notification script<br>
* This script will be called by logon detection triggers originating from Ubuntu PAM (pluggable access modules)<br>
* For this example, script is stored in `/opt/my_scripts` but you can change + filter through below<br>
  * create folder `sudo mkdir -p /opt/my_scripts`<br>
  * copy script to `/opt/my_scripts/login_notification.sh`<br>
  * edit script to replace your 2 pushover api keys `sudo nano /opt/my_scripts/login_notification.sh`<br>
  * script is for security so don't leave open permissions so can be disabled easily:<br>
    * `sudo chown root:root /opt/my_scripts/login_notification.sh`<br>
    * `sudo chmod 700 /opt/my_scripts/login_notification.sh`<br><br>
### 3:  SSH trigger<br>
* Edit sshd PAM:    `sudo nano /etc/pam.d/sshd`<br>
* add line at end:  `session optional pam_exec.so /opt/my_scripts/login_notification.sh`<br>
### 4:  Console/Terminal trigger<br>
* Edit login PAM:   `sudo nano /etc/pam.d/login`<br>
* and line near end above final @include calls:  `session optional pam_exec.so /opt/my_scripts/login_notification.sh`<br>
### 5:  GUI Login trigger (desktop Ubuntu)<br>
* N/A for cli only servers, only for Ubuntu desktop
* Edit relevant PAM:  `sudo vi /etc/pam.d/gdm-password`<br>
* and line near end (above final @include calls):  `session optional pam_exec.so /opt/my_scripts/login_notification.sh`<br>
