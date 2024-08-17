#!/bin/bash
#=====================
# IAGON STARTUP SCRIPT - for systemd to call
#=====================

#---------
# SECURITY - good practice notes
#---------
# - Nothing in this script requires sudo privileges/root and should run as low level user (ie not root)
# - This is to cover scenario where someone malicious finds way to trigger reverse shell via the iagon port forwards
#   and they would then have CLI low level access to the node.
# - The user scheduling/running node should also not have ability to edit any automated script running with root access,
#   because then the malicious user can use their access to simply edit the script running with root evelated access to
#   insert a command that assigns themselves root access ongoing next time scheduled job runs = thus gaining "privilege escalation"
#   out of their low access sandbox.  This isn't to be concerned about, just good practice to follow.

#----------------------
# PUSH MESSAGE FUNCTION - sent via pushover app (free trial/$5usd forever /device)
#----------------------
#   - requires secrets_file containing both apitoken and usrtoken
#     but will automatically ignore messaging if no account/secrets file
#   - requires curl package installed:    sudo apt-get update && sudo apt install curl
#
# Sample secrets file layout (without #), servicename not used yet (can be left out):
#apitoken=apitokenapitokenapitokenapitoken
#usrtoken=usrtokenusrtokenusrtokenusrtoken
#nodename=yournodename
#servicename=iag-cli.service
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


#---------------
# USER VARIABLES
#---------------
send_push_msgs="y"   # enable messaging (requires pushover acct)
enable_auto_upd="y"  # enable automated updates of node binary
home_folder="/home/iagon/bin"              # folder everything is running in
temp_folder="${home_folder}/tmp"           # auto-updater - temp storage, note if files in this folder autoupdater will turn off in case something failed
archive_folder="${home_folder}/archived"   # auto-updater - store historic versions in case need to revert
secrets_file="${home_folder}/secrets.txt"  # path to secrets file or blank out
log_file="${home_folder}/log.txt"          # path to log file
time_for_daily_msg=845                     # time around which will check for updates and send daily ok message

# SYSTEM VARIABLES
last_am_checks_day=""     #init for sending one OK status a day
last_failmsghour=""       #init for sending one fail msg an hour not spamming
echo "`date +"%Y%m%d_%H%M:%S"` - IAGON MONITOR INITIALISING" >> $log_file

# Log run mode
if [ "${send_push_msgs}" != "y" ]; then
    echo "`date +"%Y%m%d_%H%M:%S"` - PUSH MESSAGES OFF - manual choice" >> $log_file
elif [ -z ${secrets_file} ]; then
    send_push_msgs="n"  # no secrets means no api keys for messages = no messages
    echo "`date +"%Y%m%d_%H%M:%S"` - PUSH MESSAGES OFF - secrets not set" >> $log_file
elif [ ! -f ${secrets_file} ]; then
    send_push_msgs="n"  # no secrets = no api keys for messages = no messages
    echo "`date +"%Y%m%d_%H%M:%S"` - PUSH MESSAGES OFF - cannot find ${secrets_file}" >> $log_file
elif [ "$(apt list curl 2>&1 | grep installed | wc -l | awk '{ print $1 }')" != "1" ]; then
	if [ "${send_push_msgs}" == "y" ]; then
        send_push_msgs="n"  # cannot send push message without curl command
        echo "`date +"%Y%m%d_%H%M:%S"` - PUSH MESSAGES TURNED OFF - install curl package to enable" >> $log_file
	fi
	if [ "${enable_auto_upd}" == "y" ]; then
        enable_auto_upd="n" # cannot autoupdate without curl command
        echo "`date +"%Y%m%d_%H%M:%S"` - AUTO UPDATER TURNED OFF - install curl package to enable" >> $log_file
    fi
else
    # Load secrets
    apitoken="$(grep apitoken $secrets_file | awk -F\= '{ print $2}')"
    usrtoken="$(grep usrtoken $secrets_file | awk -F\= '{ print $2}')"
    nodename="$(grep nodename $secrets_file | awk -F\= '{ print $2}')"
    servicename="$(grep servicename $secrets_file | awk -F\= '{ print $2}')"  # not reqd if modifying systemd
    echo "`date +"%Y%m%d_%H%M:%S"` - SECRETS PARSED" >> $log_file
	# Check secrets
    [ -z $apitoken ] && send_push_msgs="n" || echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER APIKEY - `echo $apitoken | cut -c1-5`*" >> $log_file
    [ -z $usrtoken ] && send_push_msgs="n" || echo "`date +"%Y%m%d_%H%M:%S"` - PUSHOVER USRKEY - `echo $usrtoken | cut -c1-5`*" >> $log_file
    [ ${send_push_msgs} == "n" ] && echo "`date +"%Y%m%d_%H%M:%S"` - PUSH MESSAGES OFF - cannot parse tokens from secrets" >> $log_file \
	                           || echo "`date +"%Y%m%d_%H%M:%S"` - PUSH MESSAGES ON" >> $log_file
fi
# Autoupdate folders ok?
if [ "${enable_auto_upd}" == "y" ]; then
    mkdir -p ${temp_folder} 2>&1
	mkdir -p ${archive_folder} 2>&1
    if [ \( ! -d ${temp_folder} -o ! -d ${archive_folder} \) ]; then
        enable_auto_upd="n" # cannot autoupdate when folders issue
        echo "`date +"%Y%m%d_%H%M:%S"` - AUTO UPDATER TURNED OFF - problems setting up temp+archive folders" >> $log_file
    elif [ $(ls -1 ${temp_folder} | wc -l) -ne 0 ]; then
        enable_auto_upd="n" # cannot autoupdate when folders issue
        echo "`date +"%Y%m%d_%H%M:%S"` - AUTO UPDATER TURNED OFF - tmp folder not empty, maybe failed previous run" >> $log_file
        PUSHMSG="IAGON INIT CHANGE\n${nodename}\n Box: `uname -n`\n TURNING OFF UPDATES\n OLD FILES FOUND\n Date: `date`"
	    [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
	fi
fi


#----------
# MAIN LOOP
#----------
while true; do
    if ! pgrep -f "${home_folder}/iag-cli-linux" > /dev/null; then
        # NODE FIRST INITIALISATION
        echo "`date +"%Y%m%d_%H%M:%S"` - NODE PROCESS NOT FOUND" >> $log_file
        echo "`date +"%Y%m%d_%H%M:%S"` - TRIGGERING NODE INITIALISATION" >> $log_file
        ${home_folder}/iag-cli-linux start
		sleep 5
	    # Verify node initialised
		if [[ "`echo $(${home_folder}/iag-cli-linux get:status 2>&1) | grep up | wc -l | awk '{ print $1 }'`" == "1" ]]; then
           echo "`date +"%Y%m%d_%H%M:%S"` - NODE INITIALISED OK" >> $log_file
           # Log node version
		   sleep 5
           running_node_version="v$(${home_folder}/iag-cli-linux --version 2>&1 | awk '{ print $1 }')"
           echo "`date +"%Y%m%d_%H%M:%S"` - NODE VERSION - ${running_node_version}" >> $log_file
           PUSHMSG="IAGON OK START\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}\n Date: `date`"
	       [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
		else
           echo "`date +"%Y%m%d_%H%M:%S"` - NODE INITIALISATION FAILURE" >> $log_file
           PUSHMSG="IAGON INIT FAIL\n${nodename}\n Box: `uname -n`\n Date: `date`"
	       [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
        fi
    else
	    # NODE PROCESS PRESENT - BUT IS IT WORKING
		curr_statdata=$(${home_folder}/iag-cli-linux get:status 2>&1)
		sleep 5
        if [[ "`echo ${curr_statdata} | grep up | wc -l | awk '{ print $1 }'`" == "1" ]]; then
		    # NODE IS OK
		    # get running node version if not done already
			[ -z $running_node_version ] && running_node_version="v$(${home_folder}/iag-cli-linux --version 2>&1 | awk '{ print $1 }')"  && sleep 3
		    # has daily check/message been sent yet?
            curr_hhmm=$(date +%_H%M)
			curr_am_checks_day="$(date +%Y%m%d)"
            echo "`date +"%Y%m%d_%H%M:%S"` - NODE IS OK" >> $log_file
            if [ \( ${curr_hhmm#0} -ge ${time_for_daily_msg#0} -a "${curr_am_checks_day}" != "${last_am_checks_day}" \) ]; then
			    # RUN ONCE A DAY CHECKS
                online_node_version=`curl --silent "https://api.github.com/repos/Iagonorg/mainnet-node-CLI/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/'`
				if [ "${running_node_version}" == "${online_node_version}" ]; then
				    # No updates, send once a day confirmation process is alive
                    PUSHMSG="IAGON OK\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}\n Date: `date`"
                    [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
				elif [ "${enable_auto_upd}" == "n" ]; then
				    # Updates off, but notify one is available
                    PUSHMSG="IAGON UPDATEABLE\n${nodename}\n Box: `uname -n`\n Running: ${running_node_version}\n Online: ${online_node_version}\n UPDATE TURNED OFF\n Date: `date`"
                    [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
				elif [ "${enable_auto_upd}" == "y" ]; then
				    #-----------------
					# NEW NODE VERSION - attempt update
                    echo "`date +"%Y%m%d_%H%M:%S"` - UPDATING NODE ${running_node_version} -> ${online_node_version}" >> $log_file
					# Download + set perms
					wget "https://github.com/Iagonorg/mainnet-node-CLI/releases/download/${online_node_version}/iag-cli-linux" -q -P ${temp_folder} >> $log_file 2>&1
					downloaded=$?
                    if [ \( ${downloaded} -ne 0 -o $(ls -1 ${temp_folder}/iag-cli-linux | wc -l) -ne 1 \) ]; then
					    # eek download failure
                        echo "`date +"%Y%m%d_%H%M:%S"` - FAIL DOWNLOADING NODE ${online_node_version}" >> $log_file
                        PUSHMSG="IAGON UPDATE FAIL\n${nodename}\n Box: `uname -n`\n DOWNLOAD ${online_node_version} FAIL\n Date: `date`"
                        [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
					else
					    chmod +x ${temp_folder}/iag-cli-linux  # set exe
                        # Stop/kill node
                        echo "`date +"%Y%m%d_%H%M:%S"` - STOPPING NODE" >> $log_file
		                ${home_folder}/iag-cli-linux stop >/dev/null 2>&1
						sleep 15
						if pgrep -f "${home_folder}/iag-cli-linux" > /dev/null; then
                            echo "`date +"%Y%m%d_%H%M:%S"` - KILLING NODE" >> $log_file
                            pkill -f "${home_folder}/iag-cli-linux"
							sleep 3
                        fi
					    # Move+Rename Binaries
						archive_file=${archive_folder}/iag-cli-linux_${running_node_version}
                        echo "`date +"%Y%m%d_%H%M:%S"` - Archive Binary ${archive_file}" >> $log_file
						[ -f ${archive_file} ] && mv ${archive_file} ${archive_file}_$(date +"%Y%m%d_%H%M:%S") && echo "`date +"%Y%m%d_%H%M:%S"` - YUK ARCHIVE EXISTED, PREVIOUS FUBAR SUSPECTED" >> $log_file
						mv ${home_folder}/iag-cli-linux ${archive_file} && echo "`date +"%Y%m%d_%H%M:%S"` - ARCHIVED EXISTING BINARY"    >> $log_file
						mv ${temp_folder}/iag-cli-linux ${home_folder}  && echo "`date +"%Y%m%d_%H%M:%S"` - NEW BINARY MOVED INTO PLACE" >> $log_file

					    # Start updated node
                        echo "`date +"%Y%m%d_%H%M:%S"` - RESTARTING NODE" >> $log_file
		                ${home_folder}/iag-cli-linux start >/dev/null 2>&1
			            sleep 5

						# Check updated version running or revert to previous version
            			if [[ "`echo $(${home_folder}/iag-cli-linux get:status 2>&1) | grep up | wc -l | awk '{ print $1 }'`" == "1" ]]; then
						    #-----------
							# UPDATED OK
							running_node_version="v$(${home_folder}/iag-cli-linux --version 2>&1 | awk '{ print $1 }')"  && sleep 3
                            echo "`date +"%Y%m%d_%H%M:%S"` - POST UPDATE RESTART SUCCESSFUL - now running ${running_node_version}" >> $log_file
            			    PUSHMSG="IAGON UPDATED OK\n${nodename}\n Box: `uname -n`\n Version: ${running_node_version}\n Date: `date`"
                            [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
                        else
						    #----------------
							# UPDATE FAILED - attempt to revert
                            echo "`date +"%Y%m%d_%H%M:%S"` - NODE DOWN - UPDATE RESTART FAILED" >> $log_file
							mv ${home_folder}/iag-cli-linux ${temp_folder}/iag-cli-linux-fail-${online_node_version}_$(date +"%Y%m%d_%H%M:%S")
							cp ${archive_file} ${home_folder}/iag-cli-linux
                            echo "`date +"%Y%m%d_%H%M:%S"` - NODE DOWN - NODE VERSIONS REVERTED" >> $log_file
                            # Start old node version
                            echo "`date +"%Y%m%d_%H%M:%S"` - RESTARTING NODE" >> $log_file
		                    ${home_folder}/iag-cli-linux start >/dev/null 2>&1
			                sleep 5
                            echo "`date +"%Y%m%d_%H%M:%S"` - POST UPDATE FAIL REVERT RESTART TRIGGERED" >> $log_file
            			    PUSHMSG="IAGON UPDATE FUBAR\nREVERTED NODE VERSION\n${nodename}\n Box: `uname -n`\n MANUALLY CHECK ON IT\nTEMP FOLDER LEFT FAILURE\nTO BLOCK NEXT RUN\n Date: `date`"
                            [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
                        fi
					fi
				else
				    # Should never end up here, note issue
                    echo "`date +"%Y%m%d_%H%M:%S"` - BAD ERROR - wtf-1" >> $log_file
                    PUSHMSG="IAGON CODE ERROR\n${nodename}\n Box: `uname -n`\n ErrCode: wtf-1\n Date: `date`"
                    [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
				fi
			    last_am_checks_day="$(date +%Y%m%d)"
            fi
	    else
		    #-------------
			# NODE FAILING - try to restart and then check
            curr_failmsghour=$(date +%Y%m%d%H)
            [ "`echo $curr_statdata | grep not | wc -l | awk '{ print $1 }'`" == "1" ] && nodestate="DOWN" || nodestate="UNKNOWN"

		    # ATTEMPT STOP+START
            echo "`date +"%Y%m%d_%H%M:%S"` - NODE STATE ${nodestate} - STOPPING" >> $log_file
		    ${home_folder}/iag-cli-linux stop >/dev/null 2>&1
		    sleep 30
            echo "`date +"%Y%m%d_%H%M:%S"` - RESTARTING NODE" >> $log_file
		    ${home_folder}/iag-cli-linux start >/dev/null 2>&1
			sleep 5

			# CHECK RESTART
			if [[ "`echo $(${home_folder}/iag-cli-linux get:status 2>&1) | grep up | wc -l | awk '{ print $1 }'`" == "1" ]]; then
                echo "`date +"%Y%m%d_%H%M:%S"` - RESTART SUCCESSFUL" >> $log_file
			    PUSHMSG="IAGON RESTARTED OK\n${nodename}\n Box: `uname -n`\n Date: `date`"
                [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
            else
                echo "`date +"%Y%m%d_%H%M:%S"` - NODE DOWN - RESTART FAILED" >> $log_file
                if [ "${curr_failmsghour}" != "${last_failmsghour}" ]; then
			        PUSHMSG="IAGON FAIL\n${nodename}\n Box: `uname -n`\n Date: `date`"
                    [ "${send_push_msgs}" == "y" ] && _pushmessage "${apitoken}" "${usrtoken}" "${PUSHMSG}"
				    last_failmsghour="$(date +%Y%m%d%H)"
				fi
            fi
		fi
	fi

	sleep 300
done
