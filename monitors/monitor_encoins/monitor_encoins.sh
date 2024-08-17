#!/bin/bash
#===============
# ENCS MONITOR - light relay notifications via push message
#===============
#    - sent via pushover.net app (free trial/$5usd forever /device)
#    - create specific api key for encoins(+optionally load logo thumbnail)
#    - sends hourly message if node failed
#    - sends daily message if all ok
#    - requires secrets_file containing both pushover apitoken and usrtoken (see below)
#    - requires curl+jq packages installed:    sudo apt-get update && sudo apt install curl jq
#    - schedule via crontab to start on reboot (!!!never run as root, unless you lock script access down to root only!!!)
#         crontab -e
#         @reboot /path_to_this_script.sh
#
# Sample secrets file layout (without #), servicename not used yet (can be left out):
#usrtoken=usrtokenusrtokenusrtokenusrtoken
#apitoken=apitokenapitokenapitokenapitoken
#nodename=yournodename
#servicename=xxxx.service

#--------
# HISTORY
# v0.2 - beta
# v0.3 - fix package missing checks bug
# v0.4 - notification on startup

#-------------
# PUSH MESSAGE
_pushmessage() {
   apitoken="${1}"
   usrtoken="${2}"
   pushmessage="${3}"
   curl -s --connect-timeout 5 \
        --form-string "token=${apitoken}" \
        --form-string "user=${usrtoken}" \
        --form-string "message=`echo -e ${pushmessage}`" \
        https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
}


#------------
# NODE STATUS
_node_on_nw() {
    relay_check=$(curl "${nodeurl}:3000/status" -X POST -H "Content-Type: application/json" --data '"MaxAdaWithdraw"')
    [[ $relay_check  == "{\"contents"* ]] && echo "y" || echo "n"
}


#---------------
# USER VARIABLES - change to suit
enable_vers_check="y"                       # enable check for new node binary
exe_folder="/home/encs/encoins/bin"         # folder containing binary
start_folder="/home/encs/encoins/config"    # folder with config to start in
secrets_file="${start_folder}/secrets.txt"  # path to secrets file
time_for_daily_msg=820                      # time around which will check for updates and send daily ok message
log_folder="${start_folder}/logs"
log_file="${log_folder}/monitor.log"


#-----------------
# SYSTEM VARIABLES
last_am_checks_day=""     #init as blank - date last message was sent
last_failmsghour=""       #init as blank - last hour fail message was sent (for hourly fail notifications)
encs_repo_url="https://api.github.com/repos/encryptedcoins/encoins-relay/releases/latest" #json for latest version
sent_reboot_init_msg="n"  #send one message when starting box so know service status

#----------------------
# INITIALISATION CHECKS
[ ! -d ${log_folder} ] && mkdir -p ${log_folder}
echo "`date +"%Y%m%d_%H%M:%S"` - ENCOINS MONITOR INITIALISING" >> $log_file
[ ! -f ${secrets_file} ] &&  echo "`date +"%Y%m%d_%H%M:%S"` - CANNOT FIND SECRETS: ${secrets_file}" >> $log_file && exit
[ "$(apt list curl --installed 2>&1 | grep curl | wc -l | awk '{ print $1 }')" != "1" ] && echo "`date +"%Y%m%d_%H%M:%S"` - CANNOT RUN WITHOUT CURL PACKAGE"  >> $log_file && exit
[ "$(apt list jq   --installed 2>&1 | grep jq   | wc -l | awk '{ print $1 }')" != "1" ] && echo "`date +"%Y%m%d_%H%M:%S"` - CANNOT RUN WITHOUT JQ PACKAGE"    >> $log_file && exit
# Load secrets
apitoken="$(grep apitoken $secrets_file | awk -F\= '{ print $2}')"
usrtoken="$(grep usrtoken $secrets_file | awk -F\= '{ print $2}')"
nodename="$(grep nodename $secrets_file | awk -F\= '{ print $2}')"
servicename="$(grep servicename $secrets_file | awk -F\= '{ print $2}')"  # not reqd if modifying systemd
echo "`date +"%Y%m%d_%H%M:%S"` - SECRETS PARSED" >> $log_file 
# Check secrets
[ -z $apitoken ] && echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER APIKEY MISSING" >> $log_file && exit 
[ -z $usrtoken ] && echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER USRKEY MISSING" >> $log_file && exit 
[ -z $apitoken ] || echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER APIKEY - `echo $apitoken | cut -c1-5`*" >> $log_file 
[ -z $usrtoken ] || echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER USRKEY - `echo $usrtoken | cut -c1-5`*" >> $log_file 
# file checks
[ ! -f ${start_folder}/relayConfig.json ] && echo "`date +"%Y%m%d_%H%M:%S"` - EXITING - CANT FIND: ${start_folder}/relayConfig.json" >> $log_file && exit 
nodeurl=$(cat ${start_folder}/relayConfig.json | jq -r '.delegation_ip') && echo "`date +"%Y%m%d_%H%M:%S"` - NODE URL: ${nodeurl}" >> $log_file 


#-----
# MAIN
if pgrep -f "encoins --run" > /dev/null; then # strip green text codes..
    running_node_version="$(${exe_folder}/encoins --help 2>&1 | sed -e 's/\x1b\[[0-9;]*m//g' | grep -i "relay server v" | awk '{ print $3 }')"
fi
while true; do
    # FAIL CHECKS
    if ! pgrep -f "${exe_folder}/encoins --run" > /dev/null; then
        curr_failmsghour=$(date +%Y%m%d%H)
        if [ "${curr_failmsghour}" != "${last_failmsghour}" ]; then
            PUSHMSG="ENCOINS FAIL\nPROCESS ABSENT\n${nodename}\n Box: `uname -n`\n Date: `date`"
            echo "`date +"%Y%m%d_%H%M:%S"` - FAIL: ${PUSHMSG}" >> $log_file 
            _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
            last_failmsghour="$(date +%Y%m%d%H)"
        fi
    elif [ _node_on_nw == "n" ]; then
        curr_failmsghour=$(date +%Y%m%d%H)
        if [ "${curr_failmsghour}" != "${last_failmsghour}" ]; then
            PUSHMSG="ENCOINS FAIL\nNO CURL RESP\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}\n Date: `date`"
            echo "`date +"%Y%m%d_%H%M:%S"` - FAIL: ${PUSHMSG}" >> $log_file 
            _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
            last_failmsghour="$(date +%Y%m%d%H)"
        fi
    else
    # NODE OK - message once a day+on bootup
        curr_hhmm=$(date +%_H%M)
        curr_am_checks_day="$(date +%Y%m%d)"
        if [ \( ${curr_hhmm#0} -ge ${time_for_daily_msg#0} -a "${curr_am_checks_day}" != "${last_am_checks_day}" \)  -o \( $sent_reboot_init_msg == "n" \) ]; then
            [ "${enable_vers_check}" == "y" ] && online_node_version=`curl --silent "${encs_repo_url}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'` \
                                              || online_node_version=${running_node_version}
            if [ "${running_node_version}" == "${online_node_version}" ]; then
                PUSHMSG="STATUS OK\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}\n Date: `date`"
            else
                PUSHMSG="NODE OK BUT\nUPDATE VERSION\n! MANUALLY !\n${nodename}\n Box: `uname -n`\n${running_node_version} ->\n${online_node_version}\n Date: `date`"
            fi
            echo "`date +"%Y%m%d_%H%M:%S"` - OK: ${PUSHMSG}" >> $log_file 
            _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
            last_am_checks_day="$(date +%Y%m%d)"
            sent_reboot_init_msg="y"
        fi
    fi
    sleep 300
done
