#!/bin/bash
#---------------------------------
# SETUP
#---------------------------------
# load variables from config
DIR="/root/rem-utils/auto-unregprod"
source "${DIR}/config.conf"

timestamp=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

#---------------------------------
# SCHEDULE THIS SCRIPT AS CRON
#---------------------------------
if ! crontab -l | grep -q "auto-unregprod.sh"
then
    (crontab -l ; echo "* * * * * ${DIR}/auto-unregprod.sh >> ${DIR}/auto-unregprod.log 2>&1") | crontab -
fi

#---------------------------------
# FUNCTION DECLARATIONS
#---------------------------------
get_producer_data () {
    for api in "${APIS[@]}"
    do
        result="$(remcli -u $api get table rem rem producers -L $PRODUCER_NAME -U $PRODUCER_NAME)"

        if [[ $result == *"$PRODUCER_NAME"* ]]; then
            echo "$result"
            break
        fi
    done
}

unregister () {
    for api in "${APIS[@]}"
    do
        result="$(remcli -u $api system unregprod $PRODUCER_NAME -p $PRODUCER_NAME@$PERMISSION)"

        if [[ $result == *"executed transaction"* ]]; then
            echo "$result"
            break
        fi
    done
}

#---------------------------------
# COMPARE TIMESTAMPS & UNREGISTER
#---------------------------------
now="$(date +%s)"
producer_data="$(get_producer_data)"
is_active="$(jq '.rows[0].is_active' <<< ${producer_data})"
last_produced="$(jq '.rows[0].last_block_time' -r <<< ${producer_data})"
last_produced_time=$(date -d $last_produced +"%s")
difference=$(( ($now-$last_produced_time) / 60))

if [[ $difference > $THRESHOLD ]] && [ "$is_active" -eq "1" ]; then

    remcli wallet unlock < /root/walletpass
    unreg_result="$(unregister)"

    if [[ $unreg_result == *"executed transaction"* ]]; then
        echo "${timestamp} - Unregistered due to ${difference} minutes of missed blocks."
    else
        echo "${timestamp} - Attempted to unregister due to ${difference} minutes of missed blocks, but all API endpoints failed."
    fi
fi

# update the timestamp
sed -i "s/LAST_CHECK=.*/LAST_CHECK=${timestamp}/" $DIR/config.conf