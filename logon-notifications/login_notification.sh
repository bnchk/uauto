#!/bin/bash
# NOTIFICATION SCRIPT FOR TRIGGERING PUSH MESSAGE ON LOGIN EVENTS
# Make sure to place userkey + apikey in the strings below
# We want to trigger the script only when the SSH session starts.
# To be notified also when session closes, you can watch for the "close_session" value.
# NB have set to always succeed via true but have gaps in experience here with this vs PAM required or optional
#  Will be loading as PAM optional as I dont think logic and output will fail
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
				--form-string "token=appkeyappkeyappkeyappkeyappkey" \
				--form-string "user=userkeyuserkeyuserkeyuserkeyyy" \
				--form-string "message=`echo -e $PO_MSG`" \
				https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
fi
exit 0
