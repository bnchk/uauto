::-------------------
:: RUN MONITORING JOB - scheduled on PC start in task manager
::-------------------

@echo off
TITLE MONITOR SCRIPT - Python
echo(  
echo(
echo   ##     ##  #######  ##    ## #### ########  #######  ########  
echo   ###   ### ##     ## ###   ##  ##     ##    ##     ## ##     ## 
echo   #### #### ##     ## ####  ##  ##     ##    ##     ## ##     ## 
echo   ## ### ## ##     ## ## ## ##  ##     ##    ##     ## ########  
echo   ##     ## ##     ## ##  ####  ##     ##    ##     ## ##   ##   
echo   ##     ## ##     ## ##   ###  ##     ##    ##     ## ##    ##  
echo   ##     ##  #######  ##    ## ####    ##     #######  ##     ##
echo(    
echo(  
echo    ######   ######  ########  #### ########  ######## 
echo   ##    ## ##    ## ##     ##  ##  ##     ##    ##    
echo   ##       ##       ##     ##  ##  ##     ##    ##    
echo    ######  ##       ########   ##  ########     ##    
echo         ## ##       ##   ##    ##  ##           ##    
echo   ##    ## ##    ## ##    ##   ##  ##           ##    
echo    ######   ######  ##     ## #### ##           ##    
echo(  
echo(
echo   CLOSING WINDOW WILL TERMINATE MONITOR - please leave
"C:\Users\<<YOUR-USER>>\AppData\Local\Programs\Python\Python312\python.exe" "C:\Temp\_ScheduledTasks\monitor\monitor.py"
pause
