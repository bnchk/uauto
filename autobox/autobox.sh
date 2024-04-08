#!/bin/bash
#----------
# AUTOBOX - system self maintainer - for systemd to call
#----------

# Secrets to hide
apitoken="azzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
usrtoken="uzzzzzzzzzzzzzzzzzzzzzzzzzzzzz"
service="iag-cli.service"

#======
# NOTES
#======
# - Security updates are automatically via unattendend-upgrades package once a day, sometimes without needing a reboot
#     but when it does, the box isn't rebooted just requires one at some point.  That is what this script does

#=======================
# CONFIGURATION REQUIRED
#=======================
# - To reboot without DOS style pop-up prompts stopping process needs config changed:
#	  sudo vim /etc/needrestart/needrestart.conf
#		- Outdated Daemons warning (UNcomment + change i->a):
#			- #$nrconf{restart} = 'i';  ==>  
#			- $nrconf{restart} = 'a';
#		- Kernel updates notification - UNcomment this line:   
#           - $nrconf{kernelhints} = -1;
# - To run sudo without password storage or promptingm add whole script to sudoers so everything within it is run with sudo
#      use command:  sudo visudo  # and add line at end:
#                    dog ALL=(ALL) NOPASSWD: /opt/my_scripts/autobox.sh
# - schedule once a day, run at 8:30am for now:  
#          crontab -e //  30 8 * * * sudo /opt/my_scripts/autobox.sh

#========
# HISTORY
# v0.1a - test

#========================
# FUNCTION - Push Message - send message based on parameters passed
f_pushmessage()
{
   apitoken="${1}"
   usrtoken="${2}"
   pushmessage="${3}"
   curl -s --connect-timeout 5 \
        --form-string "token=${apitoken}" \
        --form-string "user=${usrtoken}" \
        --form-string "message=`echo -e ${pushmessage}`" \
        https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
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
}


#===================
# MAIN - MAIN - MAIN 
#===================
max_days_without_reboot=21  # max number of days to let standard updates go without applying+updating
f_checkupdates  #load variables with update counts

# Days since last reboot: https://stackoverflow.com/questions/28353409/bash-format-uptime-to-show-days-hours-minutes
rebooted_days_ago_q=`uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0}'`
# Any updates (put in one variable for days since reboot check as simpler)
total_update_q=$(expr $security_dist_q + $security_stnd_q + $standard_dist_q + $standard_stnd_q)

# Trigger reboot:  required_f -o- tailscale -o- gt30+updates
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
   pushmessage="Box: `uname -n`\n User:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}"
else
   #-----------
   # UPDATE BOX - stop service, apply patches if existing, and reboot
   #-----------
   systemctl is-active --quiet ${service} && node_state_pre=1 || node_state_pre=0
   [ $node_state_pre -eq 1 ] && sudo systemctl stop ${service} >/dev/null 2>&1 && sleep 3
   systemctl is-active --quiet ${service} && node_state_post=1 || node_state_post=0
   if [ $node_state_post -eq 0 ]; then
      pushmessage="Box: `uname -n`\n TempMsg-PreUpdates\nIf OK after time\nDelete msg"    # TEMP MESSAGE CAN DELETE ONE DAY IF IT IS STABLE
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}"
      # Update box
	  sudo apt-get update && sudo apt-get upgrade -y && sudo apt-get dist-upgrade -y && sudo apt autoremove -y && sleep 2
      pushmessage="Box: `uname -n`\nUPDATED+REBOOTING\nUser:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}"
      sleep 5
	  # Boom
	  sudo reboot now
   else
      #----
	  # EEK - Failed to stop service - send for help
      pushmessage="Box: `uname -n`\nHELP ME - NODE\n UNSTOPPABLE\nUser:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}"
   fi
fi
exit 0
