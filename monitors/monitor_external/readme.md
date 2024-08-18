# MONITOR - EXTERNAL
For automation to be robust, boxes external to the one being monitored must be used to look back at it.  Otherwise if you notifications originate from a machine that crashed, you would receive no warning.  This scripts perform that task, configurable for different locations so different network issues can also be detected.

## SCRIPT STRUCTURE
2 scripts are platform independant (+optional extra for windows):
* `monitor_config.py` - python script containing all variables/config
* `monitor.py` - generic script driven by the config file
* `monitor.bat` - windows only - used to call python/script when scheduled


Config can be updated while leaving script running as it reloads it each check.
There are 3 levels of configurable notification
* 1 - critical - hourly message
* 2 - fix_sometime - in daily message
* 3 - supress/ignore any issue for now (but keep config record)

The config file is intended to be the same for all running instances bar the "location".
Windows bat file, need to edit location
