#!/bin/bash
#==========
# AUTOBOX - automated patch application for simple Ubuntu box
#==========

#======
# NOTES
#======
# - Security updates automatically applied via unattendend-upgrades package once a day at random time, usually without needing a reboot.
# - But when it does need a reboot, this script looks after it.
# - If tailscale can be separated and updated individually without requiring reboot attempt is made to do so.


#=======================
# REQUIRED CONFIGURATION
#=======================
# - Copy this script in to suitable location (/opt/my_scripts/autobox used as example):
#      sudo mkdir -p /opt/my_scripts/autobox
#      sudo touch /opt/my_scripts/autobox/autobox.sh
#      sudo chmod 700 /opt/my_scripts/autobox/autobox.sh
#        and copy this into it..
#
# - Create secrets file referenced in user variable below
#      sudo touch /opt/my_scripts/autobox/secrets.txt
#      sudo chmod 700 /opt/my_scripts/autobox/secrets.txt
#      sudo vi /opt/my_scripts/autobox/secrets.txt
#        usrtoken="userkeyuserkeyuserkeyuserkeyzz"   #user
#        apitoken="apikeyapikeyapikeyapikeyapikey"   #application key
#        service="whateveritis.service"              #optional service that is to be stopped
#
# - To reboot without DOS style pop-up prompts stopping process needs config changed:
#     sudo vim /etc/needrestart/needrestart.conf
#      - Outdated Daemons warning (UNcomment + change i->a) so #$nrconf{restart} = 'i';  ==> $nrconf{restart} = 'a';
#          sudo sed -i "/#\$nrconf{restart} = 'i';/s/.*/\$nrconf{restart} = 'a';/" /etc/needrestart/needrestart.conf
#      - Kernel updates notification - UNcomment this line - $nrconf{kernelhints} = -1;
#          sudo sed -i "/#\$nrconf{kernelhints} = -1;/s/.*/\$nrconf{kernelhints} = -1;/" /etc/needrestart/needrestart.conf
#
# - To prevent sudo password request/storing password - whitelist whole script to sudoers so everything within it is run with sudo,
#   in this example it is for a user called bossy (change username and path to script to suit):
#      use command:  sudo visudo  # and add line at end:
#                    bossy ALL=(ALL) NOPASSWD: /opt/my_scripts/autobox/autobox.sh
#
# - schedule once a day, run at 8:30am for now, and at reboot:
#          crontab -e //  30 8 * * * sudo /opt/my_scripts/autobox/autobox.sh
#                         @reboot sudo /opt/my_scripts/autobox/autobox.sh


#========
# HISTORY
#========
# v0.1 - no service capability - was ok, just added message into HELP when cant stop service
#      - check if running already and message + exit if so
# v0.2 - changed install folder from /opt/my_scripts/ to /opt/my_scripts/autobox/
#      - remove keys into secrets file in run folder + parse these secrets
#      - remove pre reboot warning message as has had 100% ok for long enough to assume it wont hang for unknown reasons
#      - clearer message headings like AUTOBOX OK etc
# v0.3 - testing inline sed edits for /etc/needrestart/needrestart.conf
# v0.4 - separate tailscale package application update in case reboot not required for it alone
#      - add priority to push messages:
#        - all ok=-2, tailscale_only=0, full upd/rebooting/errors=1
#        - on iOS -2=no popup/vibrate/watch but lists in history=>rely on monitors to know box is up (may change later)
#      - add tailscale version number into standard message after update 0/1 status
#      - ensure tailscale optional, boxes without it won't fail


#========================
# FUNCTION - Push Message - send message based on parameters passed
f_pushmessage()
{
   apitoken="${1}"
   usrtoken="${2}"
   pushmessage="${3}"
   priority="${4}"
   curl -s --connect-timeout 5 \
        --form-string "token=${apitoken}" \
        --form-string "user=${usrtoken}" \
        --form-string "priority=${priority}" \
        --form-string "message=`echo -e ${pushmessage}`" \
        https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
   sleep 3
}

#=========================
# FUNCTION - Check Updates - put how many of what updates into variables
f_checkupdates() {
   sudo apt-get update >/dev/null 2>&1 #need everything up to date to compare
   security_dist_q=$(apt-get -s dist-upgrade -V 2>&1 | grep "^Inst" | grep "security" | wc -l | awk '{ print $1 }')
   security_stnd_q=$(apt-get -s upgrade -V 2>&1 | grep "^Inst" | grep "security" | wc -l | awk '{ print $1 }')
   standard_dist_q=$(apt-get -s dist-upgrade -V 2>&1 | grep "^Inst" | grep -v "security" | wc -l | awk '{ print $1 }')
   standard_stnd_q=$(apt-get -s upgrade -V 2>&1 | grep "^Inst" | grep -v "security" | wc -l | awk '{ print $1 }')
   tailscale_upd_q=$(apt-get -s upgrade -V 2>&1 | grep "^Inst" | grep "tailscale" | wc -l | awk '{ print $1 }')
   [ -f /var/run/reboot-required ] && reboot_reqd_f=1 || reboot_reqd_f=0
   
   # Days since last reboot: https://stackoverflow.com/questions/28353409/bash-format-uptime-to-show-days-hours-minutes
   rebooted_days_ago_q=`uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0}'`
   # Any updates (put in one variable for days since reboot check as simpler)
   total_update_q=$(expr $security_dist_q + $security_stnd_q + $standard_dist_q + $standard_stnd_q)
}


#============
# VARIABLES - change as needed
max_days_without_reboot=21  # max number of days to let standard updates go without applying+updating
secrets_file="/opt/my_scripts/autobox/secrets.txt"  # path to secrets file
priority_silent="-2"
priority_std="0"
priority_high="1"

#===================
# MAIN - MAIN - MAIN 
#===================
#secrets 
[ ! -f ${secrets_file} ] && exit  #pointless..
apitoken="$(cat $secrets_file | grep -v ^# | grep apitoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
usrtoken="$(cat $secrets_file | grep -v ^# | grep usrtoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
service="$(cat $secrets_file  | grep -v ^# | grep service  | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
[ -z $apitoken ] && exit 
[ -z $usrtoken ] && exit 
[ -z $service ]  && service="ok-just-updates"

# Is script already running?
if [ "$(pidof -o %PPID -x $(basename $0))" != "" ]; then 
   pushmessage="HELP LIKELY\nNEEDED!!\n$(basename $0)\nRUNNING TWICE\nEXITED 2ND JOB\n Box: `uname -n`\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# get update status
f_checkupdates

# Tailscale only?
# If other triggers required fall though + update everything, but check first for simple tailscale only option
# then recheck this didn't cause reboot flag itself
[ $(dpkg -s tailscale | grep -i version | wc -l) -eq 1 ] && tailscale_curr_v="$(tailscale version | head -1 | awk '{ print $1 }')" || tailscale_curr_v="n/a"
if [ \( $rebooted_days_ago_q -lt $max_days_without_reboot \) -a \( $reboot_reqd_f -eq 0 \) -a \( $tailscale_upd_q -ne 0 \) ]; then
   # update tailscale only
   sudo apt install tailscale -y >/dev/null 2>&1 && sleep 2
   tailscale_post_v=$(tailscale version | head -1 | awk '{ print $1 }')
   pushmessage="TAILSCALE UPDT\nBox: `uname -n`\nUser:$(whoami)\nv${tailscale_curr_v}->v${tailscale_post_v}\n Date: `date`"   
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_std}"
   f_checkupdates # refresh update status in case tailscale update itself triggered reboot required
   tailscale_curr_v=${tailscale_post_v}
fi


# Trigger reboot:  required_f -o- tailscale -o- gt_daycounter+updates
if [ \( $total_update_q -gt 0 -a $rebooted_days_ago_q -ge $max_days_without_reboot \) -o \( $reboot_reqd_f -eq 1 \) -o \( $tailscale_upd_q -ne 0 \) ]; then
   trigger_updates_f=1
else
   trigger_updates_f=0
fi

#----------------------
# UPDATE/REBOOT OR EXIT
if [ $trigger_updates_f -eq 0 ]; then
   #--------
   # OK EXIT
   #--------
   pushmessage="AUTOBOX OK\nBox: `uname -n`\n User:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q} v${tailscale_curr_v}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_silent}"
else
   #-----------
   # UPDATE BOX - stop service, apply patches if existing, and reboot
   #-----------
   systemctl is-active --quiet ${service} && node_state_pre=1 || node_state_pre=0
   [ $node_state_pre -eq 1 ] && sudo systemctl stop ${service} >/dev/null 2>&1 && sleep 3
   systemctl is-active --quiet ${service} && node_state_post=1 || node_state_post=0
   if [ $node_state_post -eq 0 ]; then
      # UPDATE BOX
      sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y && sudo apt autoremove -y && sleep 2
      pushmessage="Box: `uname -n`\nUPDATED+REBOOTING\nUser:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q} v${tailscale_curr_v}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
      sudo reboot now # Boom
   else
      #----
      # EEK - Failed to stop service - send for help
      pushmessage="HELP ME - SERVICE\nUNSTOPPABLE\nBox: `uname -n`\nService: ${service}\n\nUser:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q} v${tailscale_curr_v}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   fi
fi
exit 0
