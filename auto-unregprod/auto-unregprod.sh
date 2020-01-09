#!/bin/bash
#---------------------------------
# SETUP
#---------------------------------
# load variables from config
DIR="/root/rem-utils/auto-unregprod"
source "${DIR}/config.conf"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

#---------------------------------
# INSTALL JQ IF NECESSARY
#---------------------------------
if ! dpkg -l jq &>/dev/null; then
    sudo apt-get -qq -y install jq
    echo "${timestamp} - Installed jq package because it was missing."
fi

#---------------------------------
# SCHEDULE THIS SCRIPT AS CRON
#---------------------------------
if ! crontab -l | grep -q "auto-unregprod.sh"
then
    (crontab -l ; echo "* * * * * ${DIR}/auto-unregprod.sh >> ${DIR}/auto-unregprod.log 2>&1") | crontab -
fi

#---------------------------------
# COMPARE TIMESTAMPS & UNREGISTER
#---------------------------------
now="$(date +%s)"
last_produced="$(remcli get table rem rem producers -L $PRODUCER_NAME -U $PRODUCER_NAME | jq '.rows[0].last_block_time' -r)"
last_produced_time=$(date -d $last_produced +"%s")
difference=$(( ($now-$last_produced_time) / 60))

if [[ $difference > $THRESHOLD ]]; then
    remcli wallet unlock < /root/walletpass
    remcli -u https://remchain.remme.io system unregprod $PRODUCER_NAME -p producer@$PRODUCER_NAME
    echo "${timestamp} - Unregistered due to ${difference} minutes of missed blocks."
fi

# update the timestamp
sed -i "s/LAST_CHECK=.*/LAST_CHECK=${timestamp}/" $DIR/config.conf