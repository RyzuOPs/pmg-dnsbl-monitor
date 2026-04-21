#!/bin/bash

# ------------------------------------------------------------------------------
# Name:         pmg-dnsbl-monitor.sh
# Description:  Tests and monitors the health of DNSBL lists configured in PMG.
# Author:       Łukasz Ryszkeiwicz
# GitHub:       https://github.com/pmg-tools/pmg-dnsbl-monitor
# ------------------------------------------------------------------------------


# Add system paths to ensure Cron can find necessary binaries (postconf, host, etc.)
PATH="/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"


# --- INTERNAL CONFIGURATION (Modified by installer) ---
LOG_PATH_CONFIG=""
DEFAULT_LOG="/var/log/pmg-dnsbl-test.log"
CRON_TAG="# PMG-DNSBL-MONITOR-JOB"
SCRIPT_PATH=$(realpath "$0")



# --- FUNCTION: LOGGING ---
log_msg() {
    local FACILITY="$1"
    local MESSAGE="$2"
    local TS
    TS=$(date '+%Y-%m-%d %H:%M:%S')
    local SCRIPT_NAME
    SCRIPT_NAME=$(basename "$0" .sh)
    echo "$TS [$SCRIPT_NAME] [$FACILITY] $MESSAGE" >> "${LOG_PATH_CONFIG:-$DEFAULT_LOG}"
}

# --- FUNCTION: SHOW USAGE ---
show_usage() {
    echo "Usage: $0 {--install|--run}"
    echo ""
    echo "Options:"
    echo "  --install    Runs the installation wizard (Cron, Logrotate, Config)"
    echo "  --run        Executes DNSBL health check and logs the result"
}


# --- FUNCTION: MONITORING (RUN MODE) ---
run_monitor() {
    # Check if required tools are available
    if ! command -v postconf &> /dev/null; then
        log_msg "ERROR" "[SYSTEM] postconf not found. Check PATH configuration."
        exit 1
    fi

    # Retrieve DNSBL sites from Postfix configuration
    RAW_LIST=$(postconf -h postscreen_dnsbl_sites | tr ',' ' ')

    # Validate if any DNSBL sites are configured
    if [ -z "$(echo $RAW_LIST | tr -d '[:space:]')" ]; then
        log_msg "ERROR" "[SYSTEM] No DNSBL sites configured in PMG."
        exit 1
    fi

    # Iterate through each configured DNSBL site
    for ENTRY in $RAW_LIST; do
        # Extract domain name and strip weights (e.g., zen.spamhaus.org*2 -> zen.spamhaus.org)
        DOMAIN=$(echo $ENTRY | cut -d'*' -f1)

        # Perform DNS lookup for the test record 127.0.0.2 (reversed as 2.0.0.127)
        RESULTS=$(host -W 2 -t A 2.0.0.127.$DOMAIN 2>/dev/null | grep "has address" | awk '{print $NF}')

        # Handle cases where the DNSBL provider does not respond
        if [ -z "$RESULTS" ]; then
            log_msg "ERROR" "[$DOMAIN] Status: No response (NXDOMAIN/Timeout)"
            continue
        fi

        # Initialize status flags for analyzing multiple return codes (common for Spamhaus ZEN)
        IS_OK=false
        IS_LIMIT=false
        IS_BLOCKED=false
        OTHER_ERR=""

        # Evaluate each returned IP address
        for RES in $RESULTS; do
            case "$RES" in
                127.0.0.*) IS_OK=true ;;
                127.255.255.254) IS_LIMIT=true ;;
                127.255.255.252) IS_BLOCKED=true ;;
                *) OTHER_ERR="$RES" ;;
            esac
        done

        # Log the final status based on prioritized evaluation
        if [ "$IS_OK" = true ]; then
            log_msg "INFO" "[$DOMAIN] Status: OK"
        elif [ "$IS_LIMIT" = true ]; then
            log_msg "ERROR" "[$DOMAIN] Status: Query limit exceeded (127.255.255.254)"
        elif [ "$IS_BLOCKED" = true ]; then
            log_msg "ERROR" "[$DOMAIN] Status: Open Resolver Blocked (127.255.255.252)"
        else
            log_msg "ERROR" "[$DOMAIN] Status: Unexpected result: $OTHER_ERR"
        fi
    done
}

# --- FUNCTION: INSTALLATION (INSTALL MODE) ---
run_install() {

     # Ensure the script is run as root
     if [[ $EUID -ne 0 ]]; then
         echo "Błąd: Ten skrypt musi być uruchomiony z uprawnieniami roota!"
         exit 1
     fi

    echo "--- PMG DNSBL Monitor: Instalator ---"

    # Verify if PMG actually has any DNSBL sites to monitor
    CHECK_LIST=$(postconf -h postscreen_dnsbl_sites | tr -d '[:space:]')
    if [ -z "$CHECK_LIST" ]; then
        echo "--------------------------------------------------------------------------------"
        echo "BŁĄD: Twój Proxmox Mail Gateway nie ma skonfigurowanych list DNSRBL."
        echo "Skonfiguruj je najpierw w: Configuration -> Mail Proxy -> Options -> DNSBL Sites"
        echo "--------------------------------------------------------------------------------"
        exit 1
    fi

    # Configure log file location
    read -p "Podaj ścieżkę do logu [$DEFAULT_LOG]: " USER_LOG
    USER_LOG=${USER_LOG:-$DEFAULT_LOG}
    
    # Persist the log path inside the script's internal config
    sed -i "s|^LOG_PATH_CONFIG=.*|LOG_PATH_CONFIG=\"$USER_LOG\"|" "$SCRIPT_PATH"

    # Configure Cron schedule interval
    read -p "Co ile godzin sprawdzać listy? (1-23) [1]: " USER_HOURS
    USER_HOURS=${USER_HOURS:-1}

    # Generate logrotate configuration to prevent disk exhaustion
    echo "Tworzenie konfiguracji logrotate..."
    cat << EOF > /etc/logrotate.d/pmg-dnsbl-test
$USER_LOG {
    weekly
    rotate 4
    compress
    delaycompress
    missingok
    notifempty
    create 640 root adm
}
EOF

    # Configure Cron job (replaces existing entry instead of duplicating)
    CRON_LINE="0 */$USER_HOURS * * * $SCRIPT_PATH --run > /dev/null 2>&1 $CRON_TAG"
    if crontab -l 2>/dev/null | grep -q "$CRON_TAG"; then
        echo "Aktualizacja istniejącego zadania Cron..."
        (crontab -l | sed "/$CRON_TAG/c\\$CRON_LINE") | crontab -
    else
        echo "Dodawanie nowego zadania do Cron..."
        (crontab -l 2>/dev/null; echo "$CRON_LINE") | crontab -
    fi

    echo "------------------------------------------------"
    echo "Instalacja zakończona sukcesem!"
    echo "Autor: Łukasz Ryszkeiwicz"
    echo "Log: $USER_LOG"
    echo "Interwał: co $USER_HOURS godz."
    echo "------------------------------------------------"
}

# --- MAIN LOGIC ---
case "$1" in
    --install)
        run_install
        ;;
    --run)
        run_monitor
        ;;
    *)
        show_usage
        exit 0
        ;;
esac