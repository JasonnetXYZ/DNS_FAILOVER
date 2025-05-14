#!/bin/bash

########################################################################################
########################################################################################
##########               DNS Monitor and IP Failover version 0.17.5           ##########
##########                  Jason Rhoades (c) 2024 MIT License                ##########
####                                                                                ####
####  Script must be used together with config file in $subdomain_config.sh format. ####
####  Both script and config file must have +x permissions to run                   ####
####                                                                                ####
##########     # /usr/local/sbin/dns-mf.sh /location/of/subdomain_config.sh   ##########
##########                                                                    ##########
##########         For more information, visit the wiki page below.           ##########
##########                                                                    ##########
##########  https://wiki.worldspice.net/index.php/DNS_Monitoring_and_Failover ##########
##########                                                                    ##########
########################################################################################
########################################################################################                                                              

#exec 1> dasmbt_live_output 2>&1

#set -x
#set -v
#set -u
#trap ' >> dasmbt_live_output' read debug

# Begin Script

# Load configuration file
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

# Determine if we are handling a root domain or a subdomain
# Extracts the base name and removes the _config.sh suffix
CONFIG_BASENAME=$(basename "$CONFIG_FILE" ".sh")
if [[ "$CONFIG_BASENAME" == "root" ]]; then
    SUBDOMAIN="@"
else
    SUBDOMAIN=${CONFIG_BASENAME%_config}
fi

# Set log file name and path
LOG_PATH="/var/log/dns_mon/$DOMAIN"

# Ensure the log path exists
if [[ ! -d "$LOG_PATH" ]]; then
    mkdir -p "$LOG_PATH"
    if [[ $? -ne 0 ]]; then
        log "Failed to create log directory. Check permissions."
        exit 1
    fi
fi

# Adjust log file name for root domain
if [[ "$SUBDOMAIN" == "@" ]]; then
    LOG_FILE="$LOG_PATH/root_domain.log"
else
    LOG_FILE="$LOG_PATH/$SUBDOMAIN.log"
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
    ping -c 6 $1 > /dev/null 2>&1
    return $?
}

# Function to update DNS record
update_dns() {
    local ip=$1 
    if [[ "$SUBDOMAIN" == "root" ]] && [[ $ip == "$PRIMARY_IP" ]]; then
        # Logic to update root domain record
        sed -i "0,/$ip/{s/$SECONDARY_IP/$ip/}" $ZONE_FILE

    elif [[ "$SUBDOMAIN" == "root" ]] && [[ $ip == "$SECONDARY_IP" ]]; then
        sed -i "0,/$PRIMARY_IP/{s/$PRIMARY_IP/$ip/}" $ZONE_FILE
    else
        # Logic for subdomains remains the same
        sed -i "/$SUBDOMAIN/c\\$SUBDOMAIN IN A $ip" $ZONE_FILE
    fi
   
    # Start serial incrementation
    # Get today's date in YYYYMMDD format
    TODAY=$(date +%Y%m%d)
    
    # Extract the current serial number from the zone file
    currentSerial=$(grep "serial" $ZONE_FILE | awk '{print $1}')
    
    if [[ -z $currentSerial ]]; then
        log "No serial number found in the zone file."
        return 1
    fi

    # Extract the date part and the increment part of the serial number
    currentDate=${currentSerial:0:8}
    currentIncrement=${currentSerial:8:2}

    if [[ $TODAY -eq $currentDate ]]; then
        # If today's date matches the current date in the serial, increment the last two digits
        newIncrement=$(printf "%02d" $((10#$currentIncrement + 1)))
        newSerial="$TODAY$newIncrement"
    else
        # If today's date does not match, start a new serial with today's date and "00"
        newSerial="${TODAY}00"
    fi

    # Ensure the new serial number is greater than the old one
    if [[ $newSerial -lt $currentSerial ]]; then
        log "New serial number must be greater than the current serial number."
        return 1
    fi

    # Finish serial incrementation
    
    # Update the serial number
    sed -i "s/$currentSerial/$newSerial/g" $ZONE_FILE
    
    # reload domain
    rndc reload
    
    # Log update
    log "Serial updated for $SUBDOMAIN.$DOMAIN: $newSerial, $DOMAIN has been reloaded."
    
}

# Function to send email
send_email() {
    echo -e "Subject:$1\n\n$2" | mailx -r "$EMAIL_FROM" -s "$1" "$EMAIL_TO" "$EMAIL_CC"
}

# Initial DNS check with dig
if [[ "$SUBDOMAIN" == "@" ]]; then
    CURRENT_IP=$(dig +short $DOMAIN @$DNS_SERVER)
else
    CURRENT_IP=$(dig +short $SUBDOMAIN.$DOMAIN @$DNS_SERVER)
fi

# Update DNS if the subdomain is not set to the primary IP and is not the root domain
if [[ "$SUBDOMAIN" != "@" ]] && [ "$CURRENT_IP" != "$PRIMARY_IP" ]; then
    update_dns $PRIMARY_IP
    CURRENT_IP="$PRIMARY_IP" # Update the current IP to reflect the change
    log "Starting Monitor:"
    log "Changing to $PRIMARY_IP"
    log "$EMAIL_TO and $EMAIL_CC will receive all alerts"
else
    log "Starting Monitor:"
    if [[ "$SUBDOMAIN" == "root" ]]; then
        log "Root domain update is skipped. Monitoring started."
    else
        log "$SUBDOMAIN.$DOMAIN is already set to primary IP: $PRIMARY_IP"
    fi
    log "$EMAIL_TO and $EMAIL_CC will receive all alerts"
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
            send_email "IP Recovery Alert for $SUBDOMAIN.$DOMAIN" "Primary IP $PRIMARY_IP is back up for $SUBDOMAIN.$DOMAIN. Switched back to primary IP."
            log "$PRIMARY_IP is now the IP for $SUBDOMAIN.$DOMAIN."
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
        send_email "IP Update Alert for $SUBDOMAIN.$DOMAIN" "Primary IP $PRIMARY_IP is down for $SUBDOMAIN.$DOMAIN. Switched to secondary IP $SECONDARY_IP."
        log "$SECONDARY_IP is now the IP for $SUBDOMAIN.$DOMAIN."
        ALERT_PRIMARY_DOWN_SENT=1 # Mark that the alert has been sent
    fi

    if [[ $PRIMARY_STATUS -ne 0 ]] && [[ $SECONDARY_STATUS -ne 0 ]] && [[ $ALERT_BOTH_DOWN_SENT -eq 0 ]]; then
        send_email "Network Alert FOR $SUBDOMAIN.$DOMAIN" "Both IPs are down."
        log "Both IPs are now down for $SUBDOMAIN.$DOMAIN. Waiting for connectivity."
        ALERT_BOTH_DOWN_SENT=1 # Mark that the alert has been sent
    elif [[ $PRIMARY_STATUS -eq 0 ]] || [[ $SECONDARY_STATUS -eq 0 ]]; then
        ALERT_BOTH_DOWN_SENT=0 # Reset alert sent flag if either IP is back up
    fi

    sleep $CHECK_INTERVAL
done
