# Configuration for monitoring and updating DNS for a specific subdomain
PRIMARY_IP="192.168.1.1"
SECONDARY_IP="192.168.1.2"
ZONE_FILE="/var/named/primary/example.com"
DNS_SERVER="8.8.8.8" # Optional: Specific DNS server for dig queries
DOMAIN=example.com
EMAIL_FROM="notify@example.com"
EMAIL_TO="user@example.com"
EMAIL_CC="user@example.com"
LOG_PATH="/var/log/dns_mon/example.com/subdomain.log"
CHECK_INTERVAL=30 # In seconds
DOWNTIME_THRESHOLD=60 # In seconds
UPTIME_THRESHOLD=60 # In seconds
