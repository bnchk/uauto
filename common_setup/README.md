# COMMON SETUP - Push message + config file<br>
## PUSH MESSAGE - Create Pushover Account
* Create account on [http://pushover.net](http://pushover.net) (not affiliated, found randomly on web and works well)
* Has free 30day trial, then cost once-off USD$5 per device class lasts forever<br>
* Account creation will give you a `user-api-key` the first of two required for config file<br><br>
## PUSH MESSAGE - Install app
Install pushover app then add account details into it.<br>
From [http://pushover.net](http://pushover.net) homepage:
* [Android - play store](https://play.google.com/store/apps/details?id=net.superblock.pushover)
* [iOS - app store](https://apps.apple.com/us/app/pushover-notifications/id506088175)<br>
<br>

## PUSH MESSAGE - Create Applications
Applications are groupings for messages coming from the same system or for same reason - eg WM-AYA, IAGON, ENCOINS, Minecraft, Monitors etc
* Go to "Create Application" or [http://pushover.net/apps/build](https://pushover.net/apps/build)
* Name application, plus optionally add thumbnail image (which will appear inside push message)
* You will receive a second `application-api-key` to be used in conjunction with earlier `user api-key` in following configuration file<br><br>
## CONFIG FILE - create empty
All uauto jobs share the same configuration file `/opt/uauto/uauto.conf`.<br>
Create empty file with permissions:
   ```bash
   sudo mkdir -p  /opt/uauto && \
   sudo chmod 755 /opt/uauto && \
   sudo touch     /opt/uauto/uauto.conf && \
   sudo chmod 744 /opt/uauto/uauto.conf && \
   ```
<br>

## CONFIG FILE - add info 
Open config file:
   ```
   sudo nano /opt/uauto/uauto.conf
   ```
Add following data, replacing 2x api keys in relevant spots.  Service is optional, needed if running patcher or monitor scripts but not for login warnings
   ```
   usrtoken="userkeyuserkeyuserkeyuserkeyzz"   #pushover user
   apitoken="apikeyapikeyapikeyapikeyapikey"   #pushover application key
   service="whateveritis.service"              #optional service that is to be monitored
   ```
