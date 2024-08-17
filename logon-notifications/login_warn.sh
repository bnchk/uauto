#!/bin/bash
# LOGIN WARNINGS - Send push message on logins (ssh, terminal, GUI)
# Script is triggered on sessions start, but could also use "close_session" PAM_TYPE.
# To prevent anything freezing + locking out logins:
#  - Loading as PAM optional so hopefully would continue if it failed 
#  - true condition so push message always succeeds
#  - curl timeout set in case pushover doesn't respond

# Config file requirements - contains:
# usrtoken="userkeyuserkeyuserkeyuserkeyzz"   #user key
# apitoken="apikeyapikeyapikeyapikeyapikey"   #application key

# History:
# v0.1 - ssd+console notifications
# v0.2 - add GUI detection for desktop installs
# v0.3 - move config to shared location

# Parse config details
config_file="/opt/uauto/uauto.conf"
msg_priority=1  #1=high,0=standard,-2=silent
[ ! -f ${config_file} ] && exit
usrtoken="$(cat $config_file | grep -v ^# | grep usrtoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
apitoken="$(cat $config_file | grep -v ^# | grep apitoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
[ -z $usrtoken ] && exit 
[ -z $apitoken ] && exit 

# Notification
if [[ "$PAM_TYPE" == "open_session" ]]; then
		  # Is this console or ssh?  Is triggered from both
		  if   [ "$PAM_SERVICE" == "sshd" ];         then LoginType="SSH"
		  elif [ "$PAM_SERVICE" == "login" ];        then LoginType="CONSOLE"
		  elif [ "$PAM_SERVICE" == "gdm-password" ]; then LoginType="GUI"
		  else LoginType="MYSTERY"
		  fi
		  #Construct message
		  PO_MSG="$LoginType LOGIN\n Box: `uname -n`\n User:$PAM_USER\n From:$PAM_RHOST\n Service: $PAM_SERVICE\n TTY: $PAM_TTY\n Date: `date`"

		  #Send notification
		  curl -s --connect-timeout 5 \
				--form-string "user=${usrtoken}" \
				--form-string "token=${apitoken}" \
				--form-string "priority=${priority}" \
				--form-string "message=`echo -e $PO_MSG`" \
				https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
fi
exit 0
