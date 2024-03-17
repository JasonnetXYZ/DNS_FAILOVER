#!/bin/bash

########################################################################################
########################################################################################
##########               DNS Monitor and IP Failover version 0.15             ##########
##########                  Jason Rhoades (c) 2024 MIT License                ##########
####                                                                                ####
####  Script must be used together with config file in $subdomain_config.sh format. ####
####  Both script and config file must have +x permissions to run                   ####
####                                                                                ####
##########     # /usr/local/sbin/dns-mf.sh /location/of/subdomain_config.sh   ##########
##########                                                                    ##########
##########         For more information, visit the wiki page below.           ##########
##########                                                                    ##########
##########  https://wiki.worldspice.net/index.php/DNS_Monitoring_and_failover ##########
##########                                                                    ##########
########################################################################################
########################################################################################                                                              

# Begin Script

# Load configuration
if [ $# -eq 0 ]; then
    echo "Usage: $0 <path_to_config_file>"
    exit 1
fi

CONFIG_FILE="$1"

# Ensure the configuration file exists
if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Configuration file $CONFIG_FILE not found."
    log "Configuration file $CONFIG_FILE not found." 
    exit 1
fi

source "$CONFIG_FILE"

# Extract subdomain from the configuration file name
# This extracts the base name and then removes the _config.sh suffix
SUBDOMAIN=$(basename "$CONFIG_FILE" "_config.sh")

LOG_PATH="/var/log/dns_mon/$DOMAIN"

# Ensure the log path exists
if [[ ! -d "$LOG_PATH" ]]; then
    mkdir -p "$LOG_PATH"
    if [[ $? -ne 0 ]]; then
        echo "Failed to create log directory. Check permissions."
        exit 1
    fi
fi

# Check if the log file is writable
if [[ ! -w "$LOG_PATH/$SUBDOMAIN.log" ]]; then
    echo "Log file is not writable. Check permissions."
    exit 1
fi

# Function to log messages
log() {
    local message="$1"
    local log_time=$(date "+%B %d, %Y %H:%M:%S") # Generate a new timestamp for each log entry
    echo "$log_time - $message" >> "$LOG_PATH/$SUBDOMAIN.log"
}

# Initialize flags for sent alerts
ALERT_PRIMARY_DOWN_SENT=0
ALERT_SECONDARY_UP_SENT=0
ALERT_BOTH_DOWN_SENT=0

# Function to check IP availability
check_ip() {
    ping -c 1 $1 > /dev/null 2>&1
    return $?
}

# Function to update DNS record
update_dns() {
    local ip=$1
    sed -i "/$SUBDOMAIN/c\\$SUBDOMAIN IN A $1" $ZONE_FILE

# Get the current serial number
    SERIAL_O=$(grep "serial" $ZONE_FILE | awk '{print $1}')

# Increment the serial number
    SERIAL_N=$(($SERIAL_O + 1))

# Update the serial number
     sed -i "s/$SERIAL_O/$SERIAL_N/g" $ZONE_FILE
     log "Serial updated for $SUBDOMAIN.$DOMAIN: $SERIAL_N, $DOMAIN has been reloaded."
    rndc reload
}

# Function to send email
send_email() {
    echo -e "Subject:$1\n\n$2" | mailx -r "$EMAIL_FROM" -s "$1" "$EMAIL_TO" "$EMAIL_CC"
}

# Initial DNS check with dig
CURRENT_IP=$(dig +short $SUBDOMAIN.$DOMAIN @$DNS_SERVER)

# Update DNS if the subdomain is not set to the primary IP
if [ "$CURRENT_IP" != "$PRIMARY_IP" ]; then
    update_dns $PRIMARY_IP
    CURRENT_IP="$PRIMARY_IP" # Update the current IP to reflect the change
    log "Starting Monitor:"
    log "IP for $SUBDOMAIN.$DOMAIN is not set to primary IP. Changing to $PRIMARY_UP"
    log "$EMAIL_TO and $EMAIL_CC will recieve all alerts"
else
    log "Starting Monitor:"
    log "$SUBDOMAIN.$DOMAIN is already set to primary IP: $PRIMARY_IP"
    log "$EMAIL_TO and $EMAIL_CC will recieve all alerts"
fi


# Variables to track IP status
PRIMARY_DOWN_TIME=0
SECONDARY_DOWN_TIME=0

# Main loop
while true; do
    check_ip $PRIMARY_IP
    PRIMARY_STATUS=$?
    
    check_ip $SECONDARY_IP
    SECONDARY_STATUS=$?
    
    # Update timers based on IP status
    if [[ $PRIMARY_STATUS -ne 0 ]]; then
        PRIMARY_DOWN_TIME=$((PRIMARY_DOWN_TIME + CHECK_INTERVAL))
    else
        if [[ $PRIMARY_DOWN_TIME -ge $DOWNTIME_THRESHOLD ]] && [[ $ALERT_PRIMARY_DOWN_SENT -eq 1 ]]; then
            update_dns $PRIMARY_IP
            send_email "IP Recovery Alert" "Primary IP $PRIMARY_IP is back up for $SUBDOMAIN.$DOMAIN. Switched back to primary IP."
            log "$SECONDARY_IP is down. $PRIMARY_IP is now the IP for $SUBDOMAIN.$DOMAIN."
            ALERT_PRIMARY_DOWN_SENT=0 # Reset alert sent flag
        fi
        PRIMARY_DOWN_TIME=0
    fi

    if [[ $SECONDARY_STATUS -ne 0 ]]; then
        SECONDARY_DOWN_TIME=$((SECONDARY_DOWN_TIME + CHECK_INTERVAL))
    else
        SECONDARY_DOWN_TIME=0
    fi
    
    # Decision making based on IP status and timers
    if [[ $PRIMARY_DOWN_TIME -ge $DOWNTIME_THRESHOLD ]] && [[ $SECONDARY_STATUS -eq 0 ]] && [[ $ALERT_PRIMARY_DOWN_SENT -eq 0 ]]; then
        update_dns $SECONDARY_IP
        send_email "IP Update Alert" "Primary IP $PRIMARY_IP is down for $SUBDOMAIN. Switched to secondary IP $SECONDARY_IP."
        log "$PRIMARY_IP is down. $SECONDARY_IP is now the IP for $SUBDOMAIN.$DOMAIN."
        ALERT_PRIMARY_DOWN_SENT=1 # Mark that the alert has been sent
    fi

    if [[ $PRIMARY_STATUS -ne 0 ]] && [[ $SECONDARY_STATUS -ne 0 ]] && [[ $ALERT_BOTH_DOWN_SENT -eq 0 ]]; then
        send_email "Network Alert FOR $SUBDOMAIN" "Both IPs are down."
        log "Both IPs are now down for $SUBDOMAIN.$DOMAIN. Waiting for connectivity."
        ALERT_BOTH_DOWN_SENT=1 # Mark that the alert has been sent
    elif [[ $PRIMARY_STATUS -eq 0 ]] || [[ $SECONDARY_STATUS -eq 0 ]]; then
        ALERT_BOTH_DOWN_SENT=0 # Reset alert sent flag if either IP is back up
    fi

    sleep $CHECK_INTERVAL
done


