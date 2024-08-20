#!/usr/bin/env python
# -*- coding: utf-8 -*-

#=======================================
# CONFIGURATION DATA FOR MONITOR SCRIPTS - in python format
#=======================================

#----------------
# SCRIPT LOCATION
# INTERNAL/HOSTED/WINONLAN/TAILSCALE monitor script
#   INTERNAL  - on localNW, but no mapped drives, no VPN, direct off router
#   HOSTED    - outside local network - looking from different power supply/network
#   WINONLAN  - on windows box with localNW access to mapped drives + on VPN (can check selfhosted from external address)
#   TAILSCALE - on secure network with full access
MONITOR_LOCATION = 'INTERNAL'

#-----------------------
# SLEEP PERIOD (seconds) - 5 or 10 minutes suggested (300/600)
SLEEP_PERIOD = 300

#------------------------------
# HOUR TO SEND LOW PRIORITY MSG - 24hr format once a day message hour (somewhere within that hour + SLEEP_PERIOD)
HOUR_OF_DAY_FOR_LOW_PRIORITY_MSG = 8

#-------------
# PUSH MESSAGE - tokens for push_over account monitor group
API_TOKEN = 'apikeyapikeyapikeyapikeyapikey'
USR_TOKEN = 'usrkeyusrkeyusrkeyusrkeyusrkey'

#-------------
# IP ADDRESSES - INTERNAL/WINONLAN groups - for ping tests
# ip address, group, nice_name, priority (1-critical, 2-note infrequently, 3-ignore/off for now)
INTERNAL_IPs = [
            ['192.168.1.1',  'rtr', 'cisco',    1 ],
            ['192.168.1.6',  'nas', 'qnap',     1 ],
            ['192.168.1.10', 'sw',  'nwcabinet',1 ],
            ['192.168.1.11', 'sw',  'office',   1 ],
            ['192.168.1.13', 'sw',  'garage',   2 ],
            ['192.168.1.30', 'cam', 'entrnce',  2 ],
            ['192.168.1.31', 'cam', 'rear',     2 ],
            ]

#-------------------
# EXTERNAL ADDRESSES - ALL locations check these
# [project, boxname, ip, port(int), responsetype (json,www,ping,port), selfhosted (Y/N), priority (1-critical, 2-note infrequently, 3-ignore/off for now)]
# ResponseType notes - json - will look for json in header responses, works with port forwards
#                    - www - check if standard website is up
#                    - ping - ping box - doesn't work if through NATproxy/port forward => use port instead (to check port is open)
#                    - port - will check if that socket is open on that box
# SelfHosted notes   - for when same external ip as monitoring box location, but different VLAN etc = cannot see these boxes (unless on VPN to external address)
#                    - N=any externally hosted box, Y=will filter from INTERNAL group, but not WINONLAN
# Project notes:     - AYA(substrate) nodes - can ping if direct (ie no NAT/PortForwards/Proxy), otherwise use "port"+"json". Just no ping if behind port forward.
#                                           - protocol terminates port json call->ConnErr->indicates aya at least breathing=>hardcoded to pass json as ok for "aya"+"json"+"ConnErr"
#                                             whereas if substrate crashed would be TimeoutErr (not ConnErr) => fail.
#                                           - in future may code for opening jsonrpc port + adding FW rules, but for now will work in conjunction with on-aya monitor_aya.sh ok
#                    - encoins - external pings off, can only ping over tailscale. Needs curl to fetch response.. Another day, just port check for external for now.
EXTERNAL_IPs = [
            ['www', 'companyname', 'http://companysite.com', 0, 'www','N', 2 ],
            ['iagon', 'us-iagon', '172.97,102.41', 31313, 'json',  'Y', 1 ],
            ['encoins', 'us-encoins','54.82.187.231',3005, 'port', 'N', 1 ],
            ['aya', 'us-ayadigocn', '23.23.202.22', 30303, 'ping', 'N', 1 ],
            ['aya', 'us-ayadigocn', '23.23.202.22', 30303, 'json', 'N', 1 ],
            ['aya', 'us-ayadigocn', '23.23.202.22', 30303, 'port', 'N', 1 ],
            ['aya', 'us-ayadev1', '172.97,102.41', 30301, 'json',  'Y', 2 ],
            ['aya', 'us-ayadev1', '172.97,102.41', 30301, 'port',  'Y', 2 ],
            ['aya', 'us-ayadev2', '172.97,102.41', 30302, 'json',  'Y', 2 ],
            ['aya', 'us-ayadev2', '172.97,102.41', 30302, 'port',  'Y', 2 ],
            ['aya', 'us-ayadev3', '172.97,102.41', 30303, 'json',  'Y', 2 ],
            ['aya', 'us-ayadev3', '172.97,102.41', 30303, 'port',  'Y', 2 ],
            ['aya', 'us-ayadev4', '172.97,102.41', 30304, 'json',  'Y', 2 ],
            ['aya', 'us-ayadev4', '172.97,102.41', 30304, 'port',  'Y', 2 ]
            ]

#----------------
# TAILSCALE BOXES - [project, ip, box-name, priority (1-critical, 2-note infrequently, 3-ignore/off for now)]
TAILSCALE_IPs = [
            ['wmt',  '100.74.227.131','us-sentry1',   3],
            ['wmt',  '100.74.219.2',  'us-sentry2',   3],
            ['wmt',  '100.92.53.94',  'us-vali-t2',   3],
            ['ras',  '100.83.158.19', 'rs-travellap1',3],
            ['encoins','100.106.191.62', 'us-encoins',1],
            ['iagon','100.66.146.104','us-iagon',     1],
            ['aya','100.26.21.31',    'us-ayadev1',   1],
            ['aya','100.136.51.58',   'us-ayadev2',   2],
            ['aya','100.46.25.153',   'us-ayadev3',   2],
            ['aya','100.66.251.34',   'us-ayadev4',   2],
            ['aya','100.86.201.73',   'us-ayadev5',   2]
            ]


#-----------------------------
# NEWORK DRIVE SHARES/MAPPINGS - [ip, machine_name, drive_share_name]
# purpose: for WINONLAN - checked drives un-bitlockered for backups, scans from machine with logged on LAN access
NETWORK_SHARES = [
            ['192.168.1.40', 'spacey',   'bulkstore$'],
            ['192.168.1.43', 'cruncher1','vms$'   ],
            ['192.168.1.43', 'cruncher1','media$' ],
            ['192.168.1.43', 'cruncher1','bkup1$'],
            ['192.168.1.45', 'bkup',     'dummy$' ],
            ['192.168.1.45', 'bkup',     'DummyShareSecBak$' ]
            ]
