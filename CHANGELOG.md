Changelog

v0.16
*MAJOR UPDATE ALERT*
This update fixes the serial incrementation problem. No longer will
the current serial number be incremented by a single digit. Instead,
proper YYYYMMDD{00-99} incrementation has been implemented. 

v0.15 
Update history moved from script to changelog.
Updates include error handling for log file creation and permissions.
File name changed from dns_monitor_and_failover.sh to dns-mf.sh.

v0.14.1
Updates include extended logging using the newly introduced variables 
TIME and LOG_PATH and new function, log. 

v0.13 
Updates include alteration so config file no longer has to be in 
name directory as the main script and also includes error handling for 
the config file not being present. 


