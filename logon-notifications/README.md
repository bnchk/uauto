# Ubuntu SSH+Console+GUI Logon Push notifications<br>
Whenever there is an ssh/console/GUI login to the machine, send a custom push message notification to another device.<br>
<br>
## Step1:  Create account at pushover.net<br>
* $5 per device class perpetual licence (or can use trial period to test)<br>
* This will give you a user api key<br>
* Am not affiliated in any way, they simply looked good.  There are other choices.<br><br>
## Step2:  Create application at pushover.net <br>
* Get a secondary api-keys for free for grouping messages.<br>
* This will allow grouping of notifications by application (eg all ssh logons, or just ssh logons for certain machines)<br>
* It is used in conjunction with the user api key<br>
* Can add thumbnail for simple indication of application/group<br>
* Script uses both keys<br><br>
## Step3:  Create notification script<br>
* The notification script is what is run when ssh logon is detected.<br>
* You can place it where suits for you, and set to be only accessible by root user.<br>
* Edit it to have your user and api keys
* For example if placing script here: `/opt/my_scripts/login_notification.sh`<br>
* set permissions with:<br>
  `sudo chown root:root /opt/my_scripts/login_notification.sh`<br>
  `sudo chmod 700 /opt/my_scripts/login_notification.sh`<br><br>
## Step4:  Create PAM trigger - SSH connections<br>
* Add the following line to the end of `/etc/pam.d/sshd`  eg:<br>
`sudo vi /etc/pam.d/sshd`<br>
* and add at end the following:<br>
`# SSH login Push message notification`<br>
`session optional pam_exec.so /opt/my_scripts/login_notification.sh`<br>
## Step5:  Create PAM trigger - Console connections (eg Ubuntu Server screen)<br>
* Add the following line to the end (above final @include calls) of `/etc/pam.d/login`  eg:<br>
`sudo vi /etc/pam.d/login`<br>
* and add at end the following:<br>
`# Console text-based login Push message notification`<br>
`session optional pam_exec.so /opt/my_scripts/login_notification.sh`<br>
## Step6:  Create PAM trigger - GUI Console connections (eg Ubuntu desktop)<br>
* Add the following line to the end (above final @include calls) of `/etc/pam.d/login`  eg:<br>
`sudo vi /etc/pam.d/gdm-password`<br>
* and add at end the following:<br>
`# Console GUI-based login Push message notification`<br>
`session optional pam_exec.so /opt/my_scripts/login_notification.sh`<br>
