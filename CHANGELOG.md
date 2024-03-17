Changelog

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


########################### A NOTE ON SERIAL GENERATION #################################
## In the Worldspice implementation of Bind, the serial number for all records should  ##
## be in YYYYMMDD## format with the last two digits ranging from 00 to 99 incremented  ##
## by 1 each time the zone file is updated. However for the sake of getting this       ## 
## fail-over monitor up and running, the easiest way to handle the ever increasing     ##
## serial number is just to take the existing serial and increment it by 1.            ##
## Proper serial incrementation will be added in a later version.                      ##
#########################################################################################
