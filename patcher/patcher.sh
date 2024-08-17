#!/bin/bash
#==========
# PATCHER - automated patch management for simple Ubuntu box
#==========

#======
# NOTES
#======
# - Security updates automatically applied via unattendend-upgrades package once a day at random time, usually without needing a reboot.
# - When a security patch triggered need a reboot, this script looks after it + will also apply any non-security standard/dist updates not applied by unattendend-upgrades.
# - If tailscale can be separated and updated individually without requiring reboot attempt is made to do so.
# - openssh-server updates are performed individually if found queued up
# - grub2 updates are not performed, just notification sent (maybe better to watch them in case some unexpected prompt pops up)


#=======================
# REQUIRED CONFIGURATION
#=======================
# - Needs packages 
#      sudo apt install unattended-upgrades 
#      sudo dpkg-reconfigure --priority=low unattended-upgrades
#      sudo apt install needrestart 
#
# - Copy this script in to suitable location (/opt/uauto/patcher used as example):
#      sudo mkdir -p /opt/uauto/patcher
#      sudo touch /opt/uauto/patcher/patcher.sh
#      sudo chmod 700 /opt/uauto/patcher/patcher.sh
#        and copy this into it..
#
# - Create config file referenced in user variable below
#      sudo touch /opt/uauto/uauto.conf
#      sudo chown root:root /opt/uauto/uauto.conf
#      sudo chmod 700 /opt/uauto/uauto.conf
#      sudo vi /opt/uauto/uauto.conf
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
#   in this example replace username with your user running job + set path to script to match:
#      use command:  sudo visudo  # and add line at end:
#                    username ALL=(ALL) NOPASSWD: /opt/uauto/patcher/patcher.sh
#
# - set schedule eg here once a day at 8:30am
#          crontab -e //  30 8 * * * sudo /opt/uauto/patcher/patcher.sh


#========
# HISTORY
#========
# v0.1 - pilot test/learn mode, no service capability - was ok, just added message into HELP when cant stop service
#      - run for months to get feel for what unattended updates is doing
#      - check if running already and message + exit if so
# v0.2 - changed install folder
#      - remove keys into secrets file in run folder + parse these secrets
#      - remove pre reboot warning message as has had 100% ok for long enough to assume it wont hang for unknown reasons
#      - clearer message headings
# v0.3 - testing inline sed edits for /etc/needrestart/needrestart.conf
# v0.4 - separate tailscale package application update in case reboot not required for it alone
#      - add priority to push messages:
#        - all ok=-2, tailscale_only=0, full upd/rebooting/errors=1
#        - on iOS -2=no popup/vibrate/watch but lists in history=>rely on monitors to know box is up (may change later)
#      - add tailscale version number into standard message after update 0/1 status
#      - ensure tailscale optional, boxes without it won't fail/flag issue
# v0.5 - Bugfix/Stability - check for dpkg (package manager) getting locked out on popup confirmation windows by openssh-server (and can see grub2 will do this also)
#        - openssh-server updates run individually to suppress confirmations such as "use older config file" style confirmations
#          noting debian dpkg config method can see will do nothing on Ubuntu despite documentation saying it should suppress confirmations.
#        - grub-pc will exit with warning - it is too dangerous to automate this until it is understood more.  Maybe it will be OK
#          but halt all automation when this is detected so it can be manually analysed
#      - add check for dpkg (package manager) locked out, plus needs "dpkg --configure -a" run manually to finish confirmations
# v0.6 - Stability - add environment checks for installed packages, as appears variety between ubuntu source being VPS or Ubuntu - some don't have needrestart
#      - Stability - check required configuration was performed before allowing script to run
# v0.7 - move to /opt/uauto/patcher/patcher.sh + /opt/uauto/uauto.conf + remove from cron @reboot (leave that notification for uauto_monitor job)
#      - add flag for beta code patching - openssh_server
#      - add flag for grub patching - leave as no until have seen a few go past manually
#      - v0.7.1 - name/folder shift again, didn't fit on watchface as well

# TODO - add logging
#      - more forced killing of service before reboots if it doesn't shutdown on nice request?  
#         - But reboot would do same anyway.  
#         - Maybe instead option to pause rebooting+notify if service won't stop (eg if it is known it will corrupt blockchain by forced quit/reboot).
#      - add check for when automated updates are actually running and snoose this script for a period (maybe), has been no issue so far but
#      - centralise the storage of secrets config for different automation scripts somewhere.  May need 2 lines for logon script vs other automation.  Low priority.
#      - add something for when 50_cloud_init used to override ssh config=>no change to standard config=>no need to override to keep modified config=>super future proof. But starting to chase tail with this, so just leave it.
#      - option for days delay before tailscale update?  Sometimes they come out with patch for earlier patch, can have user set integer to delay.  But chasing tail again, probably leave as is.
#      - Maybe refuse to run if can see privesc security not done => No just note in guide it is important


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
   openssh_upd_q=$(apt-get -s upgrade -V 2>&1 | grep "^Inst" | grep "openssh-server" | wc -l | awk '{ print $1 }')
   grub_upd_q=$(apt-get -s upgrade -V 2>&1 | grep "^Inst" | grep "grub-pc" | wc -l | awk '{ print $1 }')
   [ -f /var/run/reboot-required ] && reboot_reqd_f=1 || reboot_reqd_f=0
   
   # Days since last reboot: https://stackoverflow.com/questions/28353409/bash-format-uptime-to-show-days-hours-minutes
   rebooted_days_ago_q=`uptime | awk -F'( |,|:)+' '{d=h=m=0; if ($7=="min") m=$6; else {if ($7~/^day/) {d=$6;h=$8;m=$9} else {h=$6;m=$7}}} {print d+0}'`
   # Any updates (put in one variable for days since reboot check as simpler)
   total_update_q=$(expr $security_dist_q + $security_stnd_q + $standard_dist_q + $standard_stnd_q)
}


#============
# VARIABLES - change as needed
max_days_without_reboot=21  # max number of days to let standard updates go without applying+updating
beta_code_ok="y"            # beta code = y will attempt to update comms packages - eg openssh_server + tailscale, noting openssh_server updates can have prompts for config choices which are suppressed
grub_upd_ok="n"             # allow grub into standard patch stream? Leaving as no until watched it manually update a number of times + get comfortable about variety of confirmations
config_file="/opt/uauto/uauto.conf"  # path to config file
priority_silent="-2"
priority_std="0"
priority_high="1"

#===================
# MAIN - MAIN - MAIN 
#===================
#secrets 
[ ! -f ${config_file} ] && echo "Secrets file location is too secret - not here: ${config_file}" && exit  #pointless..
apitoken="$(cat $config_file | grep -v ^# | grep apitoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
usrtoken="$(cat $config_file | grep -v ^# | grep usrtoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
service="$(cat $config_file  | grep -v ^# | grep service  | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
[ -z $apitoken ] && exit 
[ -z $usrtoken ] && exit 
[ -z $service ]  && service="ok-just-updates"

#-------------------
# ENVIRONMENT CHECKS
#-------------------
# Environment check - is package manager locked out?  (dpkg maybe stuck on prompt window forever = package installed, but not configured = cannot recover)
# Run this ahead of "is script already running" is case other instance hung on package manager issues = still get notification
if [ $(dpkg -l | grep -E '^[A-Za-z][A-Z]' | wc -l) -ne 0 ]; then 
   dpkg_failed_packages=$(dpkg -l | grep -E '^[A-Za-z][A-Z]' | awk '{ print $2 }')
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nDPKG LOCKED FOR:\n${dpkg_failed_packages}\nTry: dpkg --configure -a\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Environment check - is script already running?
if [ "$(pidof -o %PPID -x $(basename $0))" != "" ]; then 
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\n$(basename $0)\nRUNNING TWICE\nEXITED 2ND JOB\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Environment check - is unattended updates installed?
if [ $(dpkg-query -W unattended-upgrades | grep -i "no packages found" | wc -l) -eq 1 ]; then
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nMissing package\nunattended-upgrades\nPlease install\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Environment check - does unattended updates appear configured?
if [ -f /etc/apt/apt.conf.d/20auto-upgrades ]; then
   if [ $(cat /etc/apt/apt.conf.d/20auto-upgrades | grep "1" | wc -l) -gt 0 ]; then
   ua_configured=1
   else
      ua_configured=0
   fi
else
   ua_configured=0
fi
if [ ${ua_configured} -eq 0 ]; then
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nUnattended-upgrades\npackage installed\nnot configured.\nPlease configure.\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Environment check - is needrestart installed?
if [ $(dpkg-query -W needrestart | grep -i "no packages found" | wc -l) -eq 1 ]; then
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nMissing package\nneedrestart\nPlease install\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi
if [ ! -f /etc/needrestart/needrestart.conf ]; then
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nPackage needrestart\nhas issues\nPlease reinstall\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Environment check - is needrestart configured?
if [ $(cat /etc/needrestart/needrestart.conf | grep "^\$nrconf{restart} = 'a';" | wc -l) -ne 1 ]; then
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nPackage needrestart\nconfig incorrect\nset restart=a\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi
if [ $(cat /etc/needrestart/needrestart.conf | grep "^\$nrconf{kernelhints} = -1;" | wc -l) -ne 1 ]; then
   pushmessage="PATCHER ISSUE\nBox: `uname -n`\nPackage needrestart\nconfig incorrect\nset kernelhints=-1\n!!!QUITTING!!!\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi


#---------------------------
# INDIVIDUAL PACKAGE UPDATES - tailscale, openssh-server, grub-pc
#---------------------------
# If other triggers required fall though + update everything, but check first for high priority/isolated updates
# Take care these processes don't individually cause reboot flag scenario post their updating

# get update status
f_checkupdates

# OPENSSH-SERVER
if [ $openssh_upd_q -ne 0 ]; then
   if [ "$beta_code_ok" == "y" ]; then
      pushmessage="PATCHER WARN\nOPENSSH UPDATE!\nBox: `uname -n`\nWARNING-BETA CODE\nMAY LOCK UP\nPACKAGE MANAGER\nDPKG\nSTARTING NOW\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
      UCF_FORCE_CONFFOLD=1 sudo apt-get install -y openssh-server >/dev/null 2>&1
      pushmessage="PATCHER WARN\nOPENSSH UPDATE!\nBox: `uname -n`\nCOMPLETED\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   else # exit
      pushmessage="PATCHER WARN\nOPENSSH UPDATE!\nBox: `uname -n`\nEXITING AS BETA\nCODE SET TO NO.\nPATCH+REBOOT NOW\nALL MANUAL\nUNTIL THIS APPLIED\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
      exit 0
   fi
fi

# TAILSCALE
if [ $(dpkg-query -W tailscale 2>&1 | grep -i "no packages found" | wc -l) -eq 0 ]; then
   # tailscale installed
   [ $(dpkg -s tailscale | grep -i version | wc -l) -eq 1 ] && tailscale_curr_v="$(tailscale version | head -1 | awk '{ print $1 }')" || tailscale_curr_v=" n/a"
   if [ \( $rebooted_days_ago_q -lt $max_days_without_reboot \) -a \( $reboot_reqd_f -eq 0 \) -a \( $tailscale_upd_q -ne 0 \) ]; then
      # update tailscale only if nothing else
      sudo apt install tailscale -y >/dev/null 2>&1 && sleep 2
      tailscale_post_v=$(tailscale version | head -1 | awk '{ print $1 }')
      pushmessage="TAILSCALE UPDT\nBox: `uname -n`\nUser:$(whoami)\nv${tailscale_curr_v}->v${tailscale_post_v}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_std}"
      f_checkupdates # refresh update status in case tailscale update itself triggered reboot required
      tailscale_curr_v=${tailscale_post_v}
   fi
else
   tailscale_curr_v=" n/a"
fi

# GRUB-PC - exit for now, this is really dangerous to automate..
if [ $grub_upd_q -ne 0 ]; then
   if [ "$grub_upd_ok" == "y" ]; then
      pushmessage="PATCHER EEK\n!GRUB UPDATE!\nBox: `uname -n`\nWRAPPING UP IN\nSTANDARD PATCHES\nVERY BRAVE\nGOOD LUCK..\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   else
      pushmessage="PATCHER EEK\n!GRUB UPDATE!\nBox: `uname -n`\nCANNOT DO-QUITTING\nTOO RISKY\nANALYSE SCENARIO\nIF IT OCCURS\nMANUALLY APPLY\nPATCHES PLEASE\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
      exit 5
   fi
fi

# Re-check if reboot required after any individual packages
[ -f /var/run/reboot-required ] && reboot_reqd_f=1 || reboot_reqd_f=0


#----------------------
# UPDATE/REBOOT OR EXIT
#----------------------
# Trigger reboot:  required_f -o- tailscale -o- gt_daycounter+updates -o- openssh-server (but not grub yet till options seen/checked)
if [ \( $total_update_q -gt 0 -a $rebooted_days_ago_q -ge $max_days_without_reboot \) -o \( $reboot_reqd_f -eq 1 \) -o \( $tailscale_upd_q -ne 0 \) -o \( $openssh_upd_q -ne 0 \) ]; then
   trigger_updates_f=1
else
   trigger_updates_f=0
fi

if [ $trigger_updates_f -eq 0 ]; then
   #--------
   # OK EXIT
   #--------
   pushmessage="PATCHER OK\nBox: `uname -n`\n User:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q} v${tailscale_curr_v}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
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
      pushmessage="UPDATED+REBOOTING\nBox: `uname -n`\nUser:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q} v${tailscale_curr_v}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
      sudo reboot now # Boom
   else
      #----
      # EEK - Failed to stop service - send for help
      pushmessage="PATCHER EEK\nHELP ME - SERVICE\nUNSTOPPABLE\nBox: `uname -n`\nService: ${service}\n\nUser:$(whoami)\n Updates:\nSecDist:${security_dist_q}\nSecStnd:${security_stnd_q}\nStndDist:${standard_dist_q}\nStndStnd:${standard_stnd_q}\nTailscale:${tailscale_upd_q} v${tailscale_curr_v}\nRebootedAgo:${rebooted_days_ago_q}\nReboot Reqd:${reboot_reqd_f}\nTrigger Updates:${trigger_updates_f}\n Date: `date`"   
      f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   fi
fi
exit 0
