#!/bin/bash
#==============
# MONITOR-AYA - run on wm ayanode - monitor node status + check for updates
#==============
#
# - Runs on reboot via crontab @reboot under no sudo user 
# - Notifies if node started ok/not on bootup (to provide feedback after separate patching script triggers reboot)
# - Notifies hourly if issue detected (checks every 5mins at default setting)
# - Notifies if node becomes ok after being in error state (within 5mins on default)
# - Notifies once a day if OK with simple point in time stats (default silently)
# - Checks the latest version from the download site 
# - Checks node status (syncing/running) plus what block is at tip/if it is advancing with thresholds
# - nb Use separate monitoring scripts for other Windows/Linux boxes to monitor this box - to notify if this box cannot be found
# - Tested on Ubuntu Server v22.04


#=======================
# REQUIRED CONFIGURATION
#=======================
# - packages required:  jq, curl
# - Needs account at pushover.net (free trial and $5 once-off for device forever)
#
# - schedule at reboot under running user (with no sudo) - eg:
#          crontab -e //  @reboot /home/wmt/monitor_aya.sh


#========
# HISTORY
#========
# v0.1 - use minecraft server as base
# v0.2 - first version


#========
# TO DO
#========
# - maybe after stable, add auto chain restart when issues detected + visudo the script in safe spot
#   but need familiarity with what is done manually to fix varying scenarios first
# - check system memory usage/disk usage


#=============
# PUSH MESSAGE - send message based on parameters passed
#=============
f_pushmessage()
{
    apitoken="${1}"
    usrtoken="${2}"
    pushmessage="${3}"
    priority="${4}"
    f_log "PUSHMSG SENT:\n${pushmessage}\nMsg priority: ${priority}" || true #log what is being sent
    pushmessage="${pushmessage}\nDate: `date`"
    curl -s --connect-timeout 5 \
         --form-string "token=${apitoken}" \
         --form-string "user=${usrtoken}" \
         --form-string "priority=${priority}" \
         --form-string "message=`echo -e ${pushmessage}`" \
         https://api.pushover.net/1/messages.json > /dev/null 2>&1 || true
    sleep 3
}


#==========
# LOG WRITE - write different forms of log file lines
#==========
f_log() 
{
    fullarg="$@"
    if [[ "${fullarg}" == "errorstate" ]]; then
        echo -e "$(date +"%Y%m%d-%H:%M:%S"): ERROR-chainstate=${chainstate},tip_curr=${tip_curr},peers=${peers},tip_move=${tip_move},tip_move_min=${tip_move_min}" >> ${logf}
    elif [[ "${fullarg}" == "okstate" ]]; then
        echo -e "$(date +"%Y%m%d-%H:%M:%S"): OK-chainstate=${chainstate},tip_curr=${tip_curr},peers=${peers},tip_move=${tip_move},tip_move_min=${tip_move_min}" >> ${logf}
    elif [[ "${fullarg}" == "versions" ]]; then
        echo -e "$(date +"%Y%m%d-%H:%M:%S"): NODE VERSIONS running=${node_vers_running},online=${node_vers_online}" >> ${logf}
    else
        #echo -e "$(date +"%Y%m%d-%H:%M:%S")-$(printf %6s $$): ${1}" >> ${logf}
        echo -e "$(date +"%Y%m%d-%H:%M:%S"): ${fullarg}" >> ${logf}
    fi
}


#=============
# CHAIN STATUS
#=============
f_get_chainstatus() 
{
    # Fetch peers count
    tip_prev=$tip_curr
    peers=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' http://localhost:9944/ | jq '.result.peers' 2>/dev/null || echo 0)
    
    # Fetch tip block in hex
    tip_hex=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "chain_getBlock"}' http://localhost:9944/ | jq -r '.result.block.header.number' 2>/dev/null || echo "0x0")
    # convert hex to decimal after stripping 0x
    tip_curr=`echo $((16#${tip_hex:2}))`
    tip_move=$(expr $tip_curr - $tip_prev) || tip_move=0
    
    # is it syncing?
    syncstate=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "system_health"}' http://localhost:9944/ | jq '.result.isSyncing' 2>/dev/null || echo "error")
    if [ "${syncstate}" == "false" ]; then
        chainstate="ok"
    elif [ "${syncstate}" == "true" ]; then
        chainstate="syncing"
    else 
        chainstate="${syncstate}" #error
    fi
}


#=============
# NODE UPDATE?
#=============
f_node_vers_online()
{
    node_vers_online=$(curl --silent "https://api.github.com/repos/worldmobilegroup/aya-node/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/') || true
    [ -z $node_vers_online ] && node_vers_online="unknown"
}


#=====================
# VARIABLES - USER SET
#=====================
config_data="/opt/uauto/uauto.conf"  # path to data file for config - pushmsg apis and service
priority_silent="-2"                 # Message group priorities
priority_std="0"
priority_high="1"
seconds_bootup_delay=100             # seconds to wait to allow node online after bootup
seconds_sleep_loop=300               # seconds to sleep before checking everything again
peers_min=8                          # what is least number of peers before issue notification
msgheader="AYANODE"                  # text at start of all push messages
logf="/home/wmt/monitor_aya.log"     # Log file location
time_for_daily_msg=810               # time around which will check for updates and send daily ok message
tip_move_min=10                      # warn if blocks in sleep period less than this amount


#===================
# VARIABLES - SYSTEM
#===================
peers=0
tip_curr=0
tip_prev=0
tip_move=0
chainstate=""
node_vers_running=""
node_vers_online=""
rebooting=1
last_am_checks_day=""
last_failmsghour=""
last_msg_state=""


#  |====================|
#  | MAIN - MAIN - MAIN |
#  | MAIN - MAIN - MAIN |
#  |====================|
pid=$$

# READ CONFIG 
[ ! -f ${config_data} ] && echo "Secrets file location is too secret - not here: ${config_data}" && exit  #pointless..
usrtoken="$(cat $config_data | grep -v ^# | grep usrtoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
apitoken="$(cat $config_data | grep -v ^# | grep apitoken | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
service="$(cat $config_data  | grep -v ^# | grep service  | awk -F\= '{ print $2}' | awk -F\# '{ print $1 }' | sed 's/ //g' | tr -d '"')"
[ -z $usrtoken ] && exit 
[ -z $apitoken ] && exit 
[ -z $service ]  && service="nothing-found"


# LOGGING STARTUP
[ ! -f "$logf" ] && touch $logf && chmod 644 $logf
if [ ! -w "$logf" ] ; then
    pushmessage="${msgheader} HELP!\nBox: `uname -n`\n$(basename $0)\nCANNOT WRITE\nITS OWN LOG\nFILE - HELP!\n${logf}\nEXITING!!\nUser: $(whoami)"
    f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
    exit 1   
else
    f_log "--------------------------------------"
    f_log "STARTUP CONFIGURATION - pid ${pid}:"
    f_log "   config_data=${config_data}"
    f_log "   msg priorities: silent=${priority_silent},std=${priority_std},high=${priority_high}"
    f_log "   seconds_bootup_delay=${seconds_bootup_delay}"
    f_log "   seconds_sleep_loop=${seconds_sleep_loop}"
    f_log "   peers_min=${peers_min}"
    f_log "   msgheader=${msgheader}"
    f_log "   logf=${logf}"
    f_log "   time_for_daily_msg=${time_for_daily_msg}"
    f_log "   tip_move_min=${tip_move_min}"
    f_log "--------------------------------------"
fi

# DUPLICATED?
if [ $(pgrep -fc $(basename $0)) -ne 1 ]; then
    # This is bootup script - but another running = yoikes, notify + exit
    pushmessage="${msgheader} HELP!\nBox: `uname -n`\n$(basename $0)\nSTARTED ON\nBOOTUP !BUT!\nALREADY RUNNING\nEXITING...\nUser: $(whoami)"
    f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
    f_log "2ND JOB EXITING - $pid shutdown.."
    exit 1
fi

# DELAY
[ ${rebooting} -eq 1 ] && sleep $seconds_bootup_delay && f_log "SLEPT - ${seconds_bootup_delay}"


#--------
#  LOOP
#--------
while true; do
    pushmessage=""
    
    #-------------
    # ERROR CHECKS
    #-------------
    service_status=$(systemctl is-active ${service})
    # Get running node version - needs checking as currently doesn't align, just says devnet, not devnet version, option -r = raw, strips double quotes
    node_vers_running=$(curl -s -H "Content-Type: application/json" -d '{"id":1, "jsonrpc":"2.0", "method": "system_chain"}' http://localhost:9944/ | jq -r '.result' 2>/dev/null) || unset node_vers_running
    f_get_chainstatus  # refresh stats
    [ $rebooting = 1 ] && sleep $seconds_sleep_loop && f_get_chainstatus  # on startup sleep again to check tip is advancing
	
    # SERVICE CHECK
    if [ "$service_status" == "inactive" ]; then  # get running service status - NB none of this is sudo
        # eek - make sure it listed, maybe config is incorrect?
        if [ $(systemctl status ${service} 2>&1 | grep "not be found" | wc -l) -eq 1 ]; then
            pushmessage="${msgheader} HELP!\nBox: `uname -n`\nMaybe config\nissue, no\nservice called\n${service} found\nUser: $(whoami)"
        else
            pushmessage="${msgheader} EEK!\nBox: `uname -n`\nNode service\ndown!!\n${service} inactive\nhelp please\nUser: $(whoami)"
        fi
    # JSONRPC ALIVE CHECK
    elif [ -z $node_vers_running ]; then
        # check response for node version
        pushmessage="${msgheader} HELP!\nBox: `uname -n`\nFailed to determine\nrunning node\nversion from\njsonrpc call. Is\nnode down..\nUser: $(whoami)"
    # PEER COUNT
    elif [ $peers_min -gt $peers ]; then
        pushmessage="${msgheader} HELP!\nBox: `uname -n`\nPeer count ${peers}\nis less than\nminimum ${peers_min}\nPlease check!\nUser: $(whoami)"
    # TIP FROZEN
    elif [ $tip_move -lt $tip_move_min ]; then
        pushmessage="${msgheader} HELP!\nBox: `uname -n`\nTip moved ${tip_move}\nblocks in ${seconds_sleep_loop}s\nExpected min $tip_move_min\nPlease check!\nUser: $(whoami)"
    fi

    if [ "$pushmessage" != "" ]; then
        # ISSUE FOUND -> MESSAGE+LOG
        curr_failmsghour=$(date +%Y%m%d%H)
        if [ \( "${curr_failmsghour}" != "${last_failmsghour}" -o "${last_msg_state}" == "ok" \) ]; then
            # send as either times up for repeat, or first state change since ok message (if toggling states)
            last_msg_state="error"
            f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_high}"
            last_failmsghour="$(date +%Y%m%d%H)"
            rebooting=0
        fi
        f_log "errorstate"

    else
        #---------
        # OK STATE
        #---------
	    f_node_vers_online # check for new node version
        if [ $rebooting -eq 1 ]; then
            # startup message after booting
            pushmessage="${msgheader} STARTED\nBox: `uname -n`\nChainstate: ${chainstate}\nPeers: ${peers}\nTip at: ${tip_curr}\nTip move=${tip_move}\nNodeVers: ${node_vers_running}\nOnlineVers: ${node_vers_online}\nStartup OK!\nUser: $(whoami)"
            f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_std}"
            rebooting=0
        elif [ "${last_msg_state}" == "error" ]; then
            # send now as first state change since error
            pushmessage="${msgheader} NOW OK\nBox: `uname -n`\nChainstate: ${chainstate}\nPeers: ${peers}\nTip at: ${tip_curr}\nTip move=${tip_move}\nError passed!\nUser: $(whoami)"
            f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_std}"
        else
            # has daily check/message been sent yet?
            curr_hhmm=$(date +%_H%M)
            curr_am_checks_day="$(date +%Y%m%d)"
            if [ \( ${curr_hhmm#0} -ge ${time_for_daily_msg#0} -a "${curr_am_checks_day}" != "${last_am_checks_day}" \) ]; then
                if [ "${node_vers_running}" == "${node_vers_online}" ]; then 
                    pushmessage="${msgheader} OK\nBox: `uname -n`\nChainstate: ${chainstate}\nPeers: ${peers}\nTip at: ${tip_curr}\nTip move=${tip_move}\nThisNode: ${node_vers_running}\nOnlineVers: ${node_vers_online}\nUser: $(whoami)"
                    f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_silent}"
                else
                    # std message with versions at front
                    pushmessage="${msgheader} UPDT\nBox: `uname -n`\nNodeVers: ${node_vers_running}\nOnlineVers: ${node_vers_online}\nChainstate: ${chainstate}\nPeers: ${peers}\nTip at: ${tip_curr}\nTip move=${tip_move}\nUser: $(whoami)"
                    f_pushmessage "${apitoken}" "${usrtoken}" "${pushmessage}" "${priority_std}"
                fi
                last_am_checks_day="$(date +%Y%m%d)"
                f_log "versions"
            fi
            f_log "okstate"
            rebooting=0
            last_msg_state="ok"
        fi
    fi    
    sleep $seconds_sleep_loop
done

