# PUSH MESSAGE SETUP<br>
Push message functionality is enabled via account using app from [http://pushover.net](http://pushover.net)<br><br>
## CREATE ACCOUNT
* Create account on [http://pushover.net](http://pushover.net) (am not affiliated, found randomly on web and works well)
* Can use free 30day trial to test, or cost was only $5 once-off per device class as a perpetual licence<br>
* This will give you a `user api key` to put in scripts<br><br>
## INSTALL APP
* From [http://pushover.net](http://pushover.net) homepage
   * [Android - play store](https://play.google.com/store/apps/details?id=net.superblock.pushover)
   * [iOS - app store](https://apps.apple.com/us/app/pushover-notifications/id506088175)
* Add account details into app<br><br>
## CREATE AN APPLICATION
* Applications are groupings for messages coming from the same system or for same reason - eg LogonNotifications, Monitoring, Node group, etc
* Go to "Create Application" under your user account or [http://pushover.net/apps/build](https://pushover.net/apps/build)
* Give the application a name, plus is recommended (but optional) to add thumbnail image
* Application will embeded logo at start + look visually different - any small square icon is fine, some I've used are [sample thumbnails](assets/) 
* You will receive a second `application api-key` to be used in conjunction with above `user api key` in scripts - so 2 keys total
