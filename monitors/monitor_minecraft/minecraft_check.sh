#!/bin/bash
#================
# MINECRAFT CHECK - is the java jar file on box the same as latest online
#================

#======
# NOTES
#======
# - Checks the java jar file running under minecraft user to see what the currently setup version is
# - Find the latest version from the download site 
# - Send message to inform via push message app pushover
# - Run once a day and on reboot - default priority message if same version, high priority if new version available
# - Uses python and beautiful soup to extract online version
# - This was setup on Ubuntu Server v22.04


#=======================
# REQUIRED CONFIGURATION
#=======================
# - Needs Ubuntu packages :
#      sudo apt install p7zip-full jq python3-pip
#
# - Python needs:
#      pip install requests beautifulsoup4
#
# - Needs account at pushover.net (free trial and $5 once-off for device forever)
#
# - So the script can run automatically without prompting for sudo password here it is whitelisted.
#   However this may not be necessary depending on different user setups.
#   In this it was necessary to extract the currently running version of minecraft due to access permissions compartmentalisation across users
#      use command:  sudo visudo  # and add line at end:
#                    boss ALL=(ALL) NOPASSWD: /opt/my_scripts/minecraft/minecraft_check.sh
#
# - schedule once a day, eg 9:20am + at reboot under user with sudo:
#          crontab -e //  20 9 * * * sudo /opt/my_scripts/minecraft/minecraft_check.sh
#                         @reboot sudo /opt/my_scripts/minecraft/minecraft_check.sh "rbt"


#========
# HISTORY
#========
# v1.0 - starting version
# v1.1 TO DO - turn reboot off again for sleeping 

#================
# ANY PARAMETERS? - on reboot start will be passed "rbt" = set any message to high to ensure delivery
[ "$1" == "rbt" ] && rebooting=1 || rebooting=0


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


#============
# VARIABLES - change as needed
running_jar_file="/home/someuser/minecraft-server/minecraft_server.jar"             # currently running jar file
script_to_get_online_version="/opt/my_scripts/minecraft/get_online_server_vers.py"  # script to scrape onlines version
secrets_file="/opt/my_scripts/autobox/secrets.txt"  # path to secrets file (use the autoupdater one for now)
priority_std="0"
priority_high="1"
if [ ${rebooting} -eq 1 ]; then
   # Notify everything so can see server restarting ok after updates
   priority_silent="0"
   sleep_till_server_should_be_started=60 # for reboot scenarios, give the server time to startup so can check service is running ok
else
   # standard run
   priority_silent="-2"
   sleep_till_server_should_be_started=1 # should be running already
fi


#===================
# MAIN - MAIN - MAIN 
#===================
#secrets 
[ ! -f ${secrets_file} ] && echo "Secrets file location is too secret - not here: ${secrets_file}" && exit  #pointless..
apitoken="$(cat $secrets_file | grep -v ^# | grep apitoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
usrtoken="$(cat $secrets_file | grep -v ^# | grep usrtoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
service="$(cat $secrets_file  | grep -v ^# | grep service  | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
[ -z $apitoken ] && exit 
[ -z $usrtoken ] && exit 
[ -z $service ]  && service="nothing-found"


#-------------------
# ENVIRONMENT CHECKS
#-------------------
# Is service running OK?
sleep $sleep_till_server_should_be_started # ensure servers should be running if rebooted

# Environment check - is this script already running?
if [ "$(pidof -o %PPID -x $(basename $0))" != "" ]; then 
   pushmessage="HELP NEEDED!\nBox: `uname -n`\n$(basename $0)\nRUNNING TWICE\nEXITED 2ND JOB\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Is the current server file there?
if [ ! -f ${running_jar_file} ]; then
   pushmessage="MINECRAFT ISSUE!\nBox: `uname -n`\nCannot find\nMinecraft Server\njar file:\n${running_jar_file}\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi
# Is the python script to scrape web there?
if [ ! -f ${script_to_get_online_version} ]; then
   pushmessage="MINECRAFT ISSUE!\nBox: `uname -n`\nCannot find\npython script to\nscrape online versoin:\n${script_to_get_online_version}\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Get current server version
curr_vers=$(sudo 7z -ir'!version.json' -so x ${running_jar_file} | jq '.id' | sed 's/"//g')
if [ -z $curr_vers ] ; then
   pushmessage="MINECRAFT ISSUE!\nBox: `uname -n`\nFailed to extract\nrunning server\nversion from\n${running_jar_file}\n User:$(whoami)\n Date: `date`"
   f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
   exit 1   
fi

# Get online server version
online_vers=$(sudo python3 ${script_to_get_online_version})

# Get running service status
service_status=$(sudo systemctl is-active ${service})

# Construct final message
if [ "${curr_vers}" == "${online_vers}" ]; then
   if [ "${service_status}" == "active" ]; then
      pushmessage="MINECRAFT OK!\nBox: `uname -n`\nVersion ${curr_vers}\nis current version\nserver ${service_status}\n User:$(whoami)\n Date: `date`"
      msg_priority=${priority_silent}
   else   
      pushmessage="MINECRAFT ISSUE!\nBox: `uname -n`\nService ${service_status}\nVersion: ${curr_vers}\nOnline: ${online_vers}\n User:$(whoami)\n Date: `date`"
      msg_priority=${priority_high}
   fi
else
   if [ "${service_status}" == "active" ]; then
      pushmessage="UPDATE MINECRAFT!\nBox: `uname -n`\nCurrVers: ${curr_vers}\nOnline Vers: ${online_vers}\nService: ${service_status}\n User:$(whoami)\n Date: `date`"
      msg_priority=${priority_high}
   else   
      pushmessage="MINECRAFT EPIC FAIL!\nBox: `uname -n`\nCurrVers: ${curr_vers}\nOnline Vers: ${online_vers}\nService: ${service_status}\n User:$(whoami)\n Date: `date`"
      msg_priority=${priority_high}
   fi
fi
f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${msg_priority}"

exit 0
