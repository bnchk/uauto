# MONITOR IAGON (cli version)
### SCRIPT
* runs as a service monitoring iagon and restarting it if unresponsive
* sends a status update once a day (silent if all ok)
* pings notification whenever anything amiss and what it is doing to rectify
<br>

### THIS PRESUMES:
* cli iagon is running under a non-sudo user called iagon from `/home/iagon/bin`
* that uauto config is performed as per [common_setup](../../common_setup)
<br>

### SETUP SCRIPT:
* Create the monitor script:
   ```bash
   touch     /home/iagon/bin/monitor_iagon.sh && \
   chmod 700 /home/iagon/bin/monitor_iagon.sh && \
   vi        /home/iagon/bin/monitor_iagon.sh
   ```
* Copy+paste in the raw monitor script from [./monitor_iagon.sh](https://raw.githubusercontent.com/bnchk/uauto/main/monitors/monitor_iagon/monitor_iagon.sh) and save
<br>

### SETUP SERVICE:
* change to your sudo user and edit:
   ```bash
   sudo vi /etc/systemd/system/iagon.service
   ```
* paste in service details:
   ```bash
   [Unit]
   Description=IAGON CLI Service
   After=network.target
   
   [Service]
   Type=simple
   User=iagon
   Group=iagon
   ExecStart=/home/iagon/bin/monitor_iagon.sh
   ExecStop=/home/iagon/bin/iag-cli-linux stop
   WorkingDirectory=//home/iagon/bin/
   
   Restart=always
   RestartSec=60
   
   [Install]
   WantedBy=multi-user.target
   ```
* Initialise server and check it:
   ```bash
   sudo systemctl daemon-reload         && \
   sudo systemctl enable iagon.service  && \
   sudo systemctl start  iagon.service  && \
   sudo systemctl status iagon.service
   ```
