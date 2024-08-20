#!/usr/bin/env python
# -*- coding: utf-8 -*-

#   --------------------
#   |  MONITORING JOB  |
#   |  MONITORING JOB  |  v0.38
#   |  MONITORING JOB  |
#   --------------------

#--------
# NOTES - run online first to see if any config script errors, can also set testing variable to 1 for help debugging 
#       - take care with user linux service setup as, as needs to relate to user pip3 install requests was run as


#-------
# TODO - check import config module can be found prior to import eg https://stackoverflow.com/questions/14050281/how-to-check-if-a-python-module-exists-without-importing-it#14050282
#      - All OK msg - at end add list of what was parsed successfully
#      - startup delay into config for initial run for slow machines like RPi
#      - projects like encoins only respond to curl command, not external pings..  Maybe add.
#      - run as Windows service so don't have to logon, but may need python installed generically
#      - online storage option for config download to save updating all monitors, but would have to leave location etc unchanged..
#        - split out location + apikeys as never reload + download refresh the rest c&c style, should work
#      - service needs to have User=root to find python modules, next time maybe plan who they are installed as
#      - security camera folders recency check = will ensure they are working

#-----------
# REQUIRED - install Requests module:  
#  Linux:    sudo apt install python3-pip
#            pip3 install requests
#  Windows:  pip3 install requests  (after python installed)
#            maybe in C:\Users\<user>\AppData\Local\Programs\Python\Python312\Scripts\pip3

#-----------
# SCHEDULING
#    Windows - install python (https://www.python.org/downloads/)
#            - create BAT file to use for scheduling containing following 3 lines (adjust to suit)
#              @echo off
#              "C:\Users\<<user>>\AppData\Local\Programs\Python\Python312\python.exe" "C:\Temp\monitor\monitor.py"
#              pause
#            - add basic task to task scheduler to run on PC startup
#              run under standard user 30seconds after logon
#              set run folder to be install location
#              disable stop the task if it runs longer than
#              if task is running do not start a new instance
#              if task fails restart every hour
#      Linux - create systemd service - monitor.service
#            - sudo systemctl status monitor.service -> should not exist already
#            - sudo mkdir -p /opt/uauto/monitor && sudo chmod 755 /opt/uauto/monitor && sudo chown <user> /opt/uauto/monitor
#            - cp monitor.py and monitor_config.py into /opt/uauto/monitor
#            - chmod 700 *py
#            - sudo vi /etc/systemd/system/monitor.service
#              [Unit]
#              Description=Monitor service
#              #After=multi-user.target
#              After=network.target
#              
#              [Service]
#              User=<user_python_modules_installed_as-maybe_root>
#              Type=simple
#              Restart=always
#              RestartSec=60
#              WorkingDirectory=/opt/uauto/monitor
#              StandardOutput=file:/opt/uauto/monitor/stdoutput.log
#              ExecStart=/usr/bin/python3 /opt/uauto/monitor/monitor.py
#              ExecReload=/bin/kill -s HUP $MAINPID
#              KillSignal=SIGINT
#              
#              [Install]
#              WantedBy=multi-user.target
#            - sudo systemctl daemon-reload
#            - sudo systemctl enable monitor.service
#            - sudo systemctl start monitor.service
#            - systemctl status monitor.service

#-------------
# PUSH MESSAGE
#-------------
def push_message(API_TOKEN, USR_TOKEN, MESSAGE_X, PRIORITY):
    import http.client, urllib
    conn = http.client.HTTPSConnection("api.pushover.net:443")
    conn.request("POST", "/1/messages.json",
    urllib.parse.urlencode({
        "token": API_TOKEN,
        "user": USR_TOKEN,
        "message": MESSAGE_X,
        "priority": PRIORITY,
    }), { "Content-type": "application/x-www-form-urlencoded" })
    return conn.getresponse()


#-------------
# IP PING TEST
#-------------
def ping(ip_address):
    import subprocess
    # QA checks
    if ip_address.find(";") >= 0:
        return 'ERR-sql-inj'
    if ip_address.count(" ") > 0:
        return 'ERR-fmt1'
    if ip_address.count(".") != 3:
        return 'ERR-fmt2'
    # ping it
    param = '-n' if OS_TYPE=='windows' else '-c'
    if OS_TYPE=='windows': param = '-n'
    else: '-c'
    command = ['ping', param, '1', ip_address]
    result = subprocess.run(command, stdout=subprocess.PIPE)
    output = result.stdout.decode('utf8')
    if "Request timed out." in output or "100% packet loss" in output or "unreachable" in output:
        return "FAIL PING"
    return "OK"


#-------------
# IS PORT OPEN
#-------------
import socket
def is_port_open(host, port):
    # credit: https://www.codeease.net
    try:
        # create a socket object
        s = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        # set a timeout of 1 second
        s.settimeout(1)
        # try to connect to the remote host and port
        s.connect((host, port))
        # close the socket
        s.close()
        # return True if the connection was successful
        return True
    except:
        # return False if the connection was unsuccessful
        return False


#    ============
#    ||        ||
#    ||  MAIN  ||
#    ||        ||
#    ============


#-----------
# INITIALISE
testing = 0  # 1 to output runtime to console
import socket
CURRENT_MACHINE_NAME = socket.gethostname()
import platform  # os type
OS_TYPE = platform.system().lower()
import time      # sleep
from datetime import datetime, timedelta  #dates
LAST_MSG_DTTM = datetime.today() - timedelta(days=4) #fake last msg date in recent history
from importlib import reload  # to reload config in case it was changed without stopping script
import sys                    # to reload config in case it was changed without stopping script
import monitor_config         # FETCH CONFIG (in python format)
if testing == 1: print('INITIALISING: ' + CURRENT_MACHINE_NAME + ':' + monitor_config.MONITOR_LOCATION)


#-------------
# LOOP FOREVER
#-------------

while True:

    #----------
    # VARIABLES
    MESSAGE_URGENT_Q = 0      # notify hourly for urgent
    MESSAGE_INFO_ONLY_Q = 0   # notify daily for info
    MESSAGE_X = 'Box:' + CURRENT_MACHINE_NAME


    #---------------
    # CHECK LOCATION
    if monitor_config.MONITOR_LOCATION != 'INTERNAL' and monitor_config.MONITOR_LOCATION != 'EXTERNAL' \
    and monitor_config.MONITOR_LOCATION != 'WINONLAN' and monitor_config.MONITOR_LOCATION != 'TAILSCALE':
        MESSAGE_URGENT_Q += 1
        MESSAGE_X = MESSAGE_X + '\nConfigErr Location: ' + monitor_config.MONITOR_LOCATION


    #---------------------------
    # PING INTERNAL IP ADDRESSES - some of these take 2 goes to get their ship together!
    if monitor_config.MONITOR_LOCATION == 'INTERNAL' or monitor_config.MONITOR_LOCATION == 'WINONLAN':
        current_line = 0
        for z in monitor_config.INTERNAL_IPs:
            current_line += 1
            if len(z) == 4: #config field count ok
                # Break out config fields into variables
                PING_IP = z[0]
                PING_DEVICE_DESC = z[1] + '-' + z[2]
                PING_PRIORITY = z[3]   # 1-critical, 2-info, 3-ignore
                if PING_PRIORITY != 3:
                    if testing == 1: print('INTERNAL: ' + PING_DEVICE_DESC)
                    ping_result = ping(PING_IP)
                    if ping_result.startswith('ERR') or ping_result.startswith('FAIL'):
                        # try second time just in case, some switches are working, but only respond to ping after first go!
                        time.sleep(3)
                        ping_result = ping(PING_IP)
                        if ping_result.startswith('ERR') or ping_result.startswith('FAIL'):
                            if PING_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                            else: MESSAGE_INFO_ONLY_Q += 1
                            MESSAGE_X = MESSAGE_X + '\n' + PING_DEVICE_DESC + '-' + ping_result
            else:
                MESSAGE_URGENT_Q += 1
                MESSAGE_X = MESSAGE_X + '\nConfigErr IntIP line' + str(current_line)


    #---------------------------
    # EXTERNAL LIVELINESS CHECKS - check from all locations (bar INTERNAL for SELF_HOSTED boxes)
    # input format:  project, boxname, ip, port, responsetype (json,www), priority (1-critical, 2-note infrequently, 3-ignore/off for now) 
    # There is much stuffing about here as requests.get fails on website with no json/maybe header not correct so valid built into error trap as well
    try:
        import requests #, json
        current_line = 0
        for currently_checking in monitor_config.EXTERNAL_IPs:
            current_line += 1
            if len(currently_checking) == 7: #config field count ok
                # Break out config fields into variables
                PROJECT = currently_checking[0].lower()
                CHECK_BOX_NAME = currently_checking[1]
                CHECK_ADDRESS = currently_checking[2]
                CHECK_PORT = currently_checking[3]
                EXPECTED_RESPONSE = currently_checking[4].lower()
                SELF_HOSTED = currently_checking[5].lower()   
                CHECK_PRIORITY = currently_checking[6]   # 1-critical, 2-info, 3-ignore
                if not EXPECTED_RESPONSE == 'ping' and not EXPECTED_RESPONSE == 'port' and not CHECK_ADDRESS.startswith('http'):
                    CHECK_ADDRESS = "http://" + CHECK_ADDRESS
                if CHECK_PORT == 0 or EXPECTED_RESPONSE == 'ping' or EXPECTED_RESPONSE == 'port':
                    CHECK_URL = CHECK_ADDRESS
                else:
                    CHECK_URL = CHECK_ADDRESS + ':' + str(CHECK_PORT)
                if not (CHECK_PRIORITY == 3 or (monitor_config.MONITOR_LOCATION == 'INTERNAL' and SELF_HOSTED == 'y')): 
                    if testing == 1: print('EXTERNAL: ' + CHECK_BOX_NAME + ' ' + CHECK_URL + ' ' + EXPECTED_RESPONSE)
                    if EXPECTED_RESPONSE == 'ping': # does it respond to ping test
                        ping_result = ping(CHECK_URL)
                        if ping_result.startswith('ERR') or ping_result.startswith('FAIL'):
                            if CHECK_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                            else: MESSAGE_INFO_ONLY_Q += 1
                            MESSAGE_X = MESSAGE_X + '\nEXTNL:' + CHECK_BOX_NAME + '-FAIL-' + EXPECTED_RESPONSE
                            if testing == 1: print('EXTERNAL: ' + CHECK_URL + ' ' + EXPECTED_RESPONSE + ' FAIL')
                        else: 
                            if testing == 1: print('EXTERNAL: ' + CHECK_URL + ' ' + EXPECTED_RESPONSE + ' PASS')
                    elif EXPECTED_RESPONSE == 'port': # Check socket is responding/port open
                        if not is_port_open(CHECK_URL, CHECK_PORT):
                            if CHECK_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                            else: MESSAGE_INFO_ONLY_Q += 1
                            MESSAGE_X = MESSAGE_X + '\nEXTNL:' + CHECK_BOX_NAME + '-FAIL-' + EXPECTED_RESPONSE + '-' + str(CHECK_PORT)
                            if testing == 1: print('EXTERNAL: ' + CHECK_URL + ' ' + EXPECTED_RESPONSE + '-' + str(CHECK_PORT) + ' FAIL')
                        else: 
                            if testing == 1: print('EXTERNAL: ' + CHECK_URL + ' ' + EXPECTED_RESPONSE + '-' + str(CHECK_PORT) + ' PASS')
                    else: # start sifting through error trap for disguised valid responses
                        try:
                            response = requests.get(CHECK_URL, timeout=9)  # can print(response.status_code) or print(response.json())
                            if testing == 1: print('  Stat_cd: ' + str(response.status_code) + ' Json: ' + str(response.json()))
                            if (EXPECTED_RESPONSE == 'json' and 'application/json' not in response.headers.get('Content-Type','')) or ((EXPECTED_RESPONSE == 'www' and response.status_code != 200)):
                                if CHECK_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                                else: MESSAGE_INFO_ONLY_Q += 1
                                MESSAGE_X = MESSAGE_X + '\nEXTNL:' + CHECK_BOX_NAME + '-FAIL-' + EXPECTED_RESPONSE
                        except requests.exceptions.Timeout:
                            if testing == 1: print('  EXTERNAL FAILED - TIMEOUT: ' + CHECK_URL)
                            if CHECK_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                            else: MESSAGE_INFO_ONLY_Q += 1
                            MESSAGE_X = MESSAGE_X + '\nEXTNL:' + CHECK_BOX_NAME + '-TIMEOUT-' + EXPECTED_RESPONSE
                        except requests.exceptions.ConnectionError:
                            if testing == 1: print('  EXTERNAL FAILED - CONNERR: ' + CHECK_URL)
                            if not (PROJECT == 'aya' and EXPECTED_RESPONSE == 'json'):
                                if CHECK_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                                else: MESSAGE_INFO_ONLY_Q += 1
                                MESSAGE_X = MESSAGE_X + '\nEXTNL:' + CHECK_BOX_NAME + '-CONNERR-' + EXPECTED_RESPONSE
                        except Exception as error:  # Not always an error, dig more.. www+200 here is still ok
                            if testing == 1: print('  EXTERNAL ' + EXPECTED_RESPONSE + ' MAYBE FAILED: >' + CHECK_URL + '<,', error)
                            if testing == 1: print('    if www and response 200 even tho in error trap is still ok')
                            if testing == 1: print('    because of json expectations in check prior, so: CHECK TYPE=' + EXPECTED_RESPONSE + ', RC=' + str(response.status_code))
                            if ((EXPECTED_RESPONSE == 'www' and response.status_code != 200)):
                                # OK really did crap itself
                                if testing == 1: print('OK - REALLY DID CRAP ITSELF')
                                if CHECK_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                                else: MESSAGE_INFO_ONLY_Q += 1
                                MESSAGE_X = MESSAGE_X + '\nEXTNL:' + CHECK_BOX_NAME + '-FAIL-' + EXPECTED_RESPONSE
            else: #Config error
                MESSAGE_INFO_ONLY_Q += 1
                MESSAGE_X = MESSAGE_X + '\nConfigErr Extnl line' + str(current_line)
    except:
        if testing == 1: print('EXTERNAL: RequestsModule missing')
        MESSAGE_URGENT_Q += 1
        MESSAGE_X = MESSAGE_X + '\nConfigErr:Need Requests module'


    #-------------------------
    # PING TAILSCALE ADDRESSES - project, ip, box-name, priority (1-critical, 2-note infrequently, 3-ignore/off for now) 
    if monitor_config.MONITOR_LOCATION == 'TAILSCALE':
        current_line = 0
        for tsboxdetail in monitor_config.TAILSCALE_IPs:
            current_line += 1
            if len(tsboxdetail) == 4: #config field count ok
                # Break out config fields into variables
                TS_PROJECT = tsboxdetail[0]
                TS_IP = tsboxdetail[1]
                TS_BOX_NAME = tsboxdetail[2]
                TS_BOX_DESC = TS_BOX_NAME  #TS_PROJECT + '-' + TS_BOX_NAME
                TS_PRIORITY = tsboxdetail[3]   # 1-critical, 2-info, 3-ignore
                if TS_PRIORITY != 3:
                    #look for box
                    if testing == 1: print('TAILSCALE: ' + TS_BOX_DESC)
                    ping_result = ping(TS_IP)
                    if ping_result.startswith('ERR') or ping_result.startswith('FAIL'):
                        # have never seen tailscale need second attempt but why not jic
                        time.sleep(3)
                        ping_result = ping(TS_IP)
                        if ping_result.startswith('ERR') or ping_result.startswith('FAIL'):
                            if TS_PRIORITY == 1: MESSAGE_URGENT_Q += 1
                            else: MESSAGE_INFO_ONLY_Q += 1
                            MESSAGE_X = MESSAGE_X + '\n' + TS_BOX_DESC + '-' + ping_result
            else: #Config error
                MESSAGE_URGENT_Q += 1
                MESSAGE_X = MESSAGE_X + '\nConfigErr Tscale line' + str(current_line)


    #---------------------
    # NETWORK SHARE CHECKS - verify network drives are unlocked: [ip, machine-name, share-name]
    import os  # folders+files
    if monitor_config.MONITOR_LOCATION == 'WINONLAN':
        if OS_TYPE=='windows':
            current_line = 0
            for nwshare in monitor_config.NETWORK_SHARES:
                current_line += 1
                if len(nwshare) == 3: #config field count ok
                    # Break out config fields into variables
                    NWS_IP = nwshare[0]
                    NWS_BOX_NAME = nwshare[1]
                    NWS_SHARE_NAME = nwshare[2]
                    NWS_FULL_SHARE_PATH = '\\\\' + NWS_IP + '\\' + NWS_SHARE_NAME
                    if testing == 1: print('NW SHARES: ' + NWS_FULL_SHARE_PATH)
                    # Check PC visible before looking for nw share
                    nws_ping_result = ping(NWS_IP)
                    if nws_ping_result.startswith('ERR') or nws_ping_result.startswith('FAIL'):
                        # No PC = no nw share..
                        MESSAGE_INFO_ONLY_Q += 1
                        MESSAGE_X = MESSAGE_X + '\n' + NWS_BOX_NAME + '-' + nws_ping_result
                    else:
                        if not os.path.isdir(NWS_FULL_SHARE_PATH):  # fails if bitlockered
                            MESSAGE_INFO_ONLY_Q += 1
                            MESSAGE_X = MESSAGE_X + '\n\\\\' + NWS_BOX_NAME + '\\' + NWS_SHARE_NAME + ' locked'
                else: #Config error
                    MESSAGE_INFO_ONLY_Q += 1
                    MESSAGE_X = MESSAGE_X + '\nConfigErr NWshare line' + str(current_line)
        else: #Incompatible OS type
            MESSAGE_URGENT_Q += 1
            MESSAGE_X = MESSAGE_X + '\nConfig Error-WINONLAN<>' + OS_TYPE


    #-------------------------
    # TESTING CONSOLE MESSAGES
    if testing == 1:
        print('URG_Q:  ' + str(MESSAGE_URGENT_Q))
        print('INFO_Q: ' + str(MESSAGE_INFO_ONLY_Q))
        print('MESSAGE:\n' + str(MESSAGE_X))
        print('LAST MSG:' + str(LAST_MSG_DTTM))


    #-------------
    # SEND MESSAGE
    MESSAGE_X = monitor_config.MONITOR_LOCATION + '\n' + MESSAGE_X  #add msg header
    CURR_DTTM = datetime.now()
    CURR_HOUR = datetime.now().strftime("%H")
    TIME_SINCE_LAST_MSG = CURR_DTTM - LAST_MSG_DTTM
    if MESSAGE_URGENT_Q > 0 and int(divmod((TIME_SINCE_LAST_MSG.days * 24 * 60 * 60) + TIME_SINCE_LAST_MSG.seconds, 3600)[0]) >= 1:
        # hourly high priority issue
        priority = 1
        x = push_message(monitor_config.API_TOKEN,monitor_config.USR_TOKEN,MESSAGE_X,priority)
        LAST_MSG_DTTM = datetime.now()
    elif MESSAGE_INFO_ONLY_Q > 0 \
    and ((int(CURR_HOUR) >= int(monitor_config.HOUR_OF_DAY_FOR_LOW_PRIORITY_MSG)) and (CURR_DTTM.strftime("%Y%m%d") != LAST_MSG_DTTM.strftime("%Y%m%d"))):
        # once a day low priority issues only message
        priority = 0
        x = push_message(monitor_config.API_TOKEN,monitor_config.USR_TOKEN,MESSAGE_X,priority)
        LAST_MSG_DTTM = datetime.now()
    elif MESSAGE_INFO_ONLY_Q == 0 and  MESSAGE_URGENT_Q == 0 \
    and ((int(CURR_HOUR) >= int(monitor_config.HOUR_OF_DAY_FOR_LOW_PRIORITY_MSG)) and (CURR_DTTM.strftime("%Y%m%d") != LAST_MSG_DTTM.strftime("%Y%m%d"))):
        # All OK once a day message
        priority = 0
        MESSAGE_X = MESSAGE_X + '\n ALL OK :-)'
        x = push_message(monitor_config.API_TOKEN,monitor_config.USR_TOKEN,MESSAGE_X,priority)
        LAST_MSG_DTTM = datetime.now()


    #---------------------------
    # SLEEP + RELOAD CONFIG DATA
    if testing == 1: print('SLEEPING: ' + str(monitor_config.SLEEP_PERIOD) + ' :' + str(CURR_HOUR) + ' :' + str(CURR_DTTM))
    if testing == 1: print('VARIABLES: CURR_HOUR:'+ str(CURR_HOUR) + ' HOURtoMSG:' + str(monitor_config.HOUR_OF_DAY_FOR_LOW_PRIORITY_MSG) + ' currentyymdd:' + str(CURR_DTTM.strftime("%Y%m%d")) + ' lastmsgyymdd:' + str(LAST_MSG_DTTM.strftime("%Y%m%d")))
    time.sleep(monitor_config.SLEEP_PERIOD)  # have a kip b4 rescanning
    reload(monitor_config)                   # in case config updated
