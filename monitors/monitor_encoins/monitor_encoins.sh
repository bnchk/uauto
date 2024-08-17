#!/bin/bash
#===============
# ENCS MONITOR - light relay autoupdate + status notifications via push message
#===============
#    - sent via pushover.net app (free trial/$5usd forever /device)
#    - create specific api key for encoins(+optionally load logo thumbnail)
#    - sends hourly message if node failed
#    - sends daily message if all ok or updated encoins version
#    - requires secrets_file containing both pushover apitoken and usrtoken (see below)
#    - requires curl+jq packages installed:    sudo apt-get update && sudo apt install curl jq
#    - schedule monitor script via crontab to start on reboot (!!!never run as root, unless you lock script access down to root only!!!)
#      - edit crontab with crontab -e, then specify this script to startup, example is run from encoins config folder as same user that job is run by (either as service or other cron job)
#         crontab -e
#         @reboot /home/encs/encoins/config/encoins_monitor.sh >/dev/null 2>&1
#
# Sample secrets file layout (without #), servicename used for auto update, but can leave blank if running job as 
# contains the following 4 lines with your pushover usr+api tokens+node name(to recognise if you have multiple relays)+
#usrtoken=usrtokenusrtokenusrtokenusrtoken
#apitoken=apitokenapitokenapitokenapitoken
#nodename=yournodename
#servicename=xxxx.service

#---------
# MESSAGES
# - once a day with status
# - hourly if relay not working
# - autoupdating relay = when new version ready+node stopped, plus after restart

#--------
# HISTORY
# v0.2 - beta
# v0.3 - fix package missing checks bug
# v0.4 - notification on startup
# v0.5 - auto update capability + simplify log variables + update functions
# v0.6 - typo only at this point - delete this note
# v0.6.1 - notes only about where to put a revert funtion from 20240429
#        - command to get service PID:  service_pid=`systemctl show --property MainPID --value node.service`

#-----
# TODO - 20240429 - ERR5 occurred, but would have been fixed with revert function
#      - add delegation amount into daily message, maybe via maestro chain indexer query?
#      - automatic update delay - allow update delay after seeing new relay version (jic in case team patch it) = send notification saying y of x days delay b4 udpate + days changed counter
#                               - if a different version seen reset days counter
#      - secrets parsing - remove up to each lines first hash (in case comment added at end)
#      - 20240420 - process lost trigger going, but not restarting!  Maybe needs reboot/restart of process here

#---------------
# USER VARIABLES - change to suit
#---------------
enable_auto_update="y"                       # Can be: n=nothanks, m=manual (ie notify only), y=update it automatically if possible
exe_folder="/home/encs/encoins/bin"          # folder containing binary
start_folder="/home/encs/encoins/config"     # folder with config service starts in
secrets_file="${start_folder}/secrets.txt"   # path to secrets file
time_for_daily_msg=820                       # approx time to check for updates and send daily ok message, 24hr format no colon, script will autoadd leading zero
#Log file - resuse encoins log folder
log_file="${start_folder}/logs/monitor.log"  # log folder should exist as encoins creates it, adding another log file
#autoupdate folder - will autocreate if needed
archive_folder="${start_folder}/archived"    # archived folder - autoupdate=y -> store old binaries in case of reversion
sleep_b4_service_restarts=60                 # seconds that will bracket service restart trigger (if using a service/systemd)


#-----------------
# SYSTEM VARIABLES - shouldn't require changes
#-----------------
last_am_checks_day="19990101" # date last message was sent - initialise as dinosaur
last_failmsghour="1999010101" # last hour fail message was sent (for hourly fail notifications) - initialise as dinosaur
encs_repo_latest_vers_json="https://api.github.com/repos/encryptedcoins/encoins-relay/releases/latest"               #json for latest version
encs_repo_latest_vers_file="https://github.com/encryptedcoins/encoins-relay/releases/download/VERSIONNUMBER/encoins" #will substitue for VERSIONNUMBER while running
sent_reboot_init_msg="n"      #send one message when starting box so know service status
sleep_between_each_scan=300   # time spent between each scan, 300 is default - detect within 5mins


#----------------------
# PUSH MESSAGE function
#----------------------
_pushmessage() {
    if [ \( $# -eq 3 -o $# -eq 4 \) ]; then
        apitoken="${1}"
        usrtoken="${2}"
        pushmessage="${3}"
        [ $# -eq 4 ] && priority="${4}" || priority=0
        echo "`date +"%Y%m%d_%H%M:%S"` - MSGLOG: ${pushmessage}" >> $log_file
        # construct push so it will timeout/never fail, reliant on external process
        # and don't want job to hang or crash for any reason beyond my control
        curl -s --connect-timeout 5 \
            --form-string "token=${apitoken}" \
            --form-string "user=${usrtoken}" \
            --form-string "priority=${priority}" \
            --form-string "message=$(echo -e "${pushmessage}\n$(date '+%Y%m%d-%H:%M:%S')")" \
            https://api.pushover.net/1/messages.json > /dev/null 2>&1 #|| true
        response=$?
        echo "`date +"%Y%m%d_%H%M:%S"` - MSGLOG RESPONSE: $response" >> $log_file
    else
        echo "`date +"%Y%m%d_%H%M:%S"` - MSG FN CALL FAIL - sent: $#" >> $log_file
    fi
}


#---------------------
# NODE STATUS function
#---------------------
_node_on_nw() {
    relay_check=$(curl "${nodeurl}:3000/status" -X POST -H "Content-Type: application/json" --data '"MaxAdaWithdraw"' 2>/dev/null)
    [[ $relay_check  == "{\"contents"* ]] && echo "y" || echo "n"
}


#----------------------
# NODE VERSION function
#----------------------
_node_version() {
    # fetch running node version after removing green text codes
    echo "$(${exe_folder}/encoins --help 2>&1 | sed -e 's/\x1b\[[0-9;]*m//g' | grep -i "relay server v" | awk '{ print $3 }')"
}


#----------------------------
# FAILED RELAY CHECK function
#----------------------------
_failed_relay_check() {
    relay_fail_status=""
    if [ $(pgrep -f "encoins --run" | wc -l) -ne 1 ]; then  # Process not listed
        relay_fail_status="process"
    elif [ _node_on_nw == "n" ]; then # Unresponsive to WWW
        relay_fail_status="www"
    elif [ ! -z ${servicename} ]; then
        if [ $(systemctl status ${servicename} | grep -i "active (running)" | wc -l) -ne 1 ]; then  # Systemd issues (no sudo needed to check)
            relay_fail_status="service"
        fi
    elif [ -z ${servicename} ]; then
        if [ $(pgrep -f "encoins --run" | wc -l) -eq 1 ]; then #its up
            if [ $(ps -ef | grep "encoins --run" | grep -v grep | awk '{ print $3 }') -eq 1 ]; then #fix config, is systemd job!
                relay_fail_status="serviceconfigmissing"
            fi
        fi
    fi
    [ "${relay_fail_status}" != "" ] && echo "`date +"%Y%m%d_%H%M:%S"` - NODE RELAY FN ERROR: ${relay_fail_status}" >> $log_file
    echo "${relay_fail_status}"
}


#----------------------
# INITIALISATION CHECKS
#----------------------
[ ! -f ${log_file} ] && touch ${log_file} 2>&1 && sleep 1
[ ! -f ${log_file} ] && echo -e "CANNOT CREATE LOG FILE - EXITING..." && exit
echo "`date +"%Y%m%d_%H%M:%S"` - ENCOINS MONITOR INITIALISING" >> $log_file
[ ! -f ${secrets_file} ] &&  echo "`date +"%Y%m%d_%H%M:%S"` - CANNOT FIND SECRETS: ${secrets_file}" >> $log_file && exit
[ "$(apt list curl --installed 2>&1 | grep curl | wc -l | awk '{ print $1 }')" != "1" ] && echo "`date +"%Y%m%d_%H%M:%S"` - CANNOT RUN WITHOUT CURL PACKAGE"  >> $log_file && exit
[ "$(apt list jq   --installed 2>&1 | grep jq   | wc -l | awk '{ print $1 }')" != "1" ] && echo "`date +"%Y%m%d_%H%M:%S"` - CANNOT RUN WITHOUT JQ PACKAGE"    >> $log_file && exit
# Load secrets - nb servicename only used for autoupdate=y and stopping service to replace binary
apitoken="$(cat $secrets_file | grep -v ^# | grep apitoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
usrtoken="$(cat $secrets_file | grep -v ^# | grep usrtoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
nodename="$(cat $secrets_file | grep -v ^# | grep nodename | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
servicename="$(cat $secrets_file  | grep -v ^# | grep servicename  | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
echo "`date +"%Y%m%d_%H%M:%S"` - SECRETS PARSED" >> $log_file 
[ "$apitoken" = "" ] && unset apitoken
[ "$usrtoken" = "" ] && unset usrtoken
[ "$nodename" = "" ] && unset nodename
[ "$servicename" = "" ] && unset servicename
# Check secrets
[ -z $apitoken ] && echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER APIKEY MISSING" >> $log_file && exit 
[ -z $usrtoken ] && echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER USRKEY MISSING" >> $log_file && exit 
[ -z $apitoken ] || echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER APIKEY: `echo $apitoken | cut -c1-5`*" >> $log_file 
[ -z $usrtoken ] || echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER USRKEY: `echo $usrtoken | cut -c1-5`*" >> $log_file 
[ -z $nodename ] || echo "`date +"%Y%m%d_%H%M:%S"` - NODE NAME: ${nodename}" >> $log_file
# file checks
[ ! -f ${start_folder}/relayConfig.json ] && echo "`date +"%Y%m%d_%H%M:%S"` - EXITING - CANT FIND: ${start_folder}/relayConfig.json" >> $log_file && exit 
[ ! -f ${exe_folder}/encoins ] && echo "`date +"%Y%m%d_%H%M:%S"` - EXITING - CANT FIND BINARY: ${exe_folder}/encoins" >> $log_file && exit 
nodeurl=$(cat ${start_folder}/relayConfig.json | jq -r '.delegation_ip') && echo "`date +"%Y%m%d_%H%M:%S"` - NODE URL:  ${nodeurl}" >> $log_file 


#-------------------------
# AUTOUPDATE+STATUS CHECKS
#-------------------------
# verify auto update status acceptable value
echo "`date +"%Y%m%d_%H%M:%S"` - ENABLE AUTO-UPDATE VALUE: ${enable_auto_update}" >> $log_file
# Exit if not valid value
[[ "${enable_auto_update}" != [nmy] ]] && _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS EXIT\nAUTOUPDATE=${enable_auto_update}\nONLY y,n,m ALLOWED\n${nodename}\n Box: `uname -n`")" \
    && sleep 3 && exit
# Service specified, check it aligns
if [ ! -z $servicename ]; then
    # Exit if service specified but not listed in systemd
    if [ $(systemctl status ${servicename} 2>&1 | grep -i "could not be found" | wc -l) -gt 0 ]; then
        _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS EXIT\nSERVICENAME\n${servicename}\nNOT IN SYSTEMD\n${nodename}\n Box: `uname -n`")" && sleep 3 && exit
    fi
    # Exit if service listed but not active in systemd (bigger issue than moniting and needs root)
    if [ $(systemctl status ${servicename} | grep -i "active (running)" | wc -l) -ne 1 ]; then
        _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS EXIT\nAUTOUPDATE=Y\nSERVICENAME\n${servicename}\nNOT ACTIVE!\n${nodename}\n Box: `uname -n`")" && sleep 3 && exit
    fi
fi
# Exit if cannot find the binary for checking
[ "${enable_auto_update}" == [my] ] && [ $(ls -l "${exe_folder}/encoins" | wc -l) -ne 1 ] && \
    _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS EXIT\nAUTOUPDATE=Y\nCANNOT FIND EXE\n${exe_folder}/encoins\n${nodename}\n Box: `uname -n`")" \
    && sleep 3 && exit
# Autoupdate=y - does archive folder exist? (exit if can't create)
[ "${enable_auto_update}" == "y" ] && [ ! -d ${archive_folder} ] && mkdir -p ${archive_folder} && chmod 744 ${archive_folder} && \
    echo "`date +"%Y%m%d_%H%M:%S"` - CREATED ARCHIVE FOLDER - ${archive_folder}" >> $log_file && sleep 1
[ "${enable_auto_update}" == "y" ] && [ ! -d ${archive_folder} ] && \
    _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS EXIT\nCANNOT MKDIR\nARCHIVE FOLDER\n${archive_folder}\n${nodename}\n Box: `uname -n`")" \
    && sleep 3 && exit


#   ===============
#   |  MAIN LOOP  |
#   |  MAIN LOOP  |
#   |  MAIN LOOP  |
#   ===============

while true; do
    [ -f ${exe_folder}/encoins ] && running_node_version="$(_node_version)"

    #--------------
    # FAIL CHECKING
    #--------------
    failcode="$(_failed_relay_check)"
    if [ ! -z $failcode ]; then
        if [ "${curr_failmsghour}" != "${last_failmsghour}" ]; then
            if [ "${failcode}" == "process" ]; then
                # Process not listed
                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS FAIL\nPROCESS ABSENT\n${nodename}\n Box: `uname -n`")" "1"
            elif [ "${failcode}" == "www" ]; then
                # Port www not responding
                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS FAIL\nNO CURL RESP\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}")" "1"
            elif [ "${failcode}" == "service" ]; then
                # Systemd issues, service not happy
                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS FAIL\nMAYBE CONFIG\nNODE UP BUT\nSERVICE INACTIVE\n${servicename}\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}")" "1"
            elif [ "${failcode}" == "serviceconfigmissing" ]; then
                # Is a systemd job, but was not specified in config
                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS FAIL\nCONFIG SECRETS\nMISSING SERVICENAME\nWHEN IS SYSTEMD\nINITIATED\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}")" "1"
            else
                # Should never end up here
                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS FAIL\nCODE ERROR\nCHECK FKD1\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}")" "1"
            fi
            curr_failmsghour=$(date +%Y%m%d%H)
        fi
    else
    #--------
    # NODE OK - message once a day + on bootup + check for updates
    #--------
        curr_hhmm=$(date +%_H%M)
        curr_am_checks_day="$(date +%Y%m%d)"
        if [ \( ${curr_hhmm#0} -ge ${time_for_daily_msg#0} -a "${curr_am_checks_day}" != "${last_am_checks_day}" \)  -o \( "$sent_reboot_init_msg" == "n" \) ]; then
            [[ "${enable_auto_update}" == [my] ]] && online_node_version=`curl --silent "${encs_repo_latest_vers_json}" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'` \
                                              || online_node_version=${running_node_version}
            if [ "${running_node_version}" == "${online_node_version}" ]; then #all good
                [ "$sent_reboot_init_msg" == "n" ] && msg_header="STARTUP" || msg_header="STATUS"
                PUSHMSG="${msg_header} OK\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}"
            elif [ "${enable_auto_update}" == "m" ]; then #send manual update msg
                # MANUAL UPDATE
                PUSHMSG="NODE OK BUT\nNEW VERSION\nAVAILABLE FOR\nMANUAL UPDATE\n${nodename}\n Box: `uname -n`\n${running_node_version} ->\n${online_node_version}\nOR TURN ON\nAUTOUPDATE"
            else
                #----------------
                # UPGRADE ENCOINS
                #----------------
                echo "`date +"%Y%m%d_%H%M:%S"` - UPDATING NODE ${running_node_version} -> ${online_node_version}" >> $log_file
                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "ENCOINS UPGRADE\nSTARTING\n${running_node_version}->${online_node_version}\n${nodename}\n Box: `uname -n`")"
                # Download new binary
                rm -f ${archive_folder}/encoins >/dev/null 2>&1 #delete any old fubar
                wget "${encs_repo_latest_vers_file/VERSIONNUMBER/$online_node_version}" -q -P ${archive_folder} >> $log_file 2>&1
                downloaded=$?
                if [ \( ${downloaded} -ne 0 -o ! -f ${archive_folder}/encoins \) ]; then
                    # Download failure
                    PUSHMSG="HELP - FAIL!!\n${nodename}\n Box: `uname -n`\nOLD NODE RUNNING\nBUT DOWNLOAD FAIL\nVers ${online_node_version}\nFROM ${encs_repo_latest_vers_file/VERSIONNUMBER/$online_node_version}"
                else
                    #------------------
                    #DOWNLOADED UPGRADE
                    chmod 744 ${archive_folder}/encoins >/dev/null 2>&1
                    # Upgrade it - NB doing this without adding stop/start commands to visudo, just replacing running job..
                    # Tested OK+easier than relying on people to edit visudo+not corrupt their system
                    chmod +x ${archive_folder}/encoins  # set exe on new version ready
                    # Move running binary to archive (job remain live in RAM)
                    rm -f ${archive_folder}/encoins_${running_node_version} >/dev/null 2>&1
                    mv -f ${exe_folder}/encoins ${archive_folder}/encoins_${running_node_version}
                    mvout_resp=$?
                    if [ $mvout_resp -ne 0 ]; then
                        # fail moving old binary to archive
                        PUSHMSG="HELP - FAIL!!\n${nodename}\n Box: `uname -n`\nNODE UPD ERR1\nMOVE BINARY TO\n${archive_folder}/encoins_${running_node_version}\nFAILED-REVERTING"
                        cp -f ${archive_folder}/encoins_${running_node_version} ${exe_folder}/encoins >/dev/null 2>&1
                    else
                        # swap in new binary
                        mv -f ${archive_folder}/encoins ${exe_folder}/encoins
                        mv_in=$?
                        if [ $mv_in -ne 0 ]; then
                            # fail moving new binary in!
                            PUSHMSG="HELP - FAIL!!\n${nodename}\n Box: `uname -n`\nNODE UPD ERR2\nMOVE NEW BINARY\nFAILED FUBAR\nATTEMPT TO REVERT"
                            [ ! -f ${exe_folder}/encoins ] && mv -f ${archive_folder}/encoins_${running_node_version} ${exe_folder}/encoins
                        else
                            #-----------------
                            # BINARIES SWAPPED - KILL RAM RUNNING NODE + RESTART (NEW VERSION)
                            echo "`date +"%Y%m%d_%H%M:%S"` - KILLING NODE" >> $log_file
                            [ $(ps -ef | grep "encoins --run" | grep -v grep | wc -l) -eq 1 ] && kill $(ps -ef | grep "encoins --run" | grep -v grep | awk '{ print $2 }') >/dev/null 2>&1 && sleep 1
                            # Try all sorts of other stuff jic
                            pkill -f "${exe_folder}/encoins" >> $log_file 2>&1 && sleep 1
                            pkill -f "${exe_folder}/encoins --run" >> $log_file 2>&1 && sleep 1
                            pkill -f "encoins --run" >> $log_file 2>&1 && sleep 1
                            # Test for something running
                            if [ $(ps -ef | grep "encoins --run" | grep -v grep | wc -l) -gt 0 ]; then
                                # kill failed
                                PUSHMSG="HELP - FAIL!!\n${nodename}\n Box: `uname -n`\nCANNOT KILL RELAY\nTO UPDATE IT\nIS THIS MONITOR\nRUNNING AS\nSAME USER THAT\nSTARTED RELAY JOB?"
                            else
                                #------------
                                # NODE KILLED - restart now
                                [ "$servicename" != "" ] && service_type="SERVICE" || service_type="NON-SERVICE"
                                _pushmessage "${apitoken}" "${usrtoken}" "$(echo "RELAY STOPPED\nNOW RESTARTING\n${service_type} RELAY\n${nodename}\n Box: `uname -n`")"
                                echo "`date +"%Y%m%d_%H%M:%S"` - NODE KILLED" >> $log_file
                                if [ "$servicename" != "" ]; then
                                    # Service will restart in whatever time was configured, hopefully after sleep
                                    sleep $sleep_b4_service_restarts
                                    echo "`date +"%Y%m%d_%H%M:%S"` - SLEPT UNTIL HOPEFULLY SERVICE RESTARTS" >> $log_file
                                else
                                    # User must have run it manually - spawn background job
                                    (cd $start_folder; ${exe_folder}/encoins --run >/dev/null 2>&1) &
                                    sleep 2
                                    echo "`date +"%Y%m%d_%H%M:%S"` - RELAY RESTART MANUALLY SUBMITTED AS BACKGROUND JOB" >> $log_file
                                fi
                                #--------------------
                                # NODE *SHOULD* BE UP
                                sleep 30 # allow extra for boot up time of node
                                if [ $(ps -ef | grep "encoins --run" | grep -v grep | wc -l) -eq 1 ]; then #simple check for process
                                    running_node_version="$(_node_version)"
                                    if [ "${running_node_version}" != "${online_node_version}" ]; then
                                        # Fell over somewhere
                                        PUSHMSG="HELP - WEIRD!\n${nodename}\n Box: `uname -n`\nNODE UPD ERR4\nNODE NEVER UPDATED\nBUT IS RUNNING\nIMAGINE SPOOKY\nSCI-FI MUSIC"
                                    else 
                                        # YAY!!
                                        PUSHMSG="UPDATE SUCCESS\n${nodename}\n Box: `uname -n`\nVersion: ${running_node_version}"
                                    fi
                                else
                                    # TOTALLY FUBAR :-(
                                    PUSHMSG="HELP - FUBAR!!\n${nodename}\n Box: `uname -n`\nNODE UPD ERR5\nUPDATE OK\nRESTART FAILED\nTOTALLY FUBAR\nRELAY OFFLINE"
                                    # This occured 20240428 upgrading to v1.2.6.0 which did not work when replaced.
                                    # but manually restoring old version was fine
                                    # TODO have revert function call here
                                fi
                            fi
                        fi
                    fi 
                fi
            fi
            _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}" "$([[ $PUSHMSG == HELP* ]] && echo 1 || echo 0)"
            last_am_checks_day="$(date +%Y%m%d)"
            sent_reboot_init_msg="y"
        fi
    fi
    sleep $sleep_between_each_scan
done
