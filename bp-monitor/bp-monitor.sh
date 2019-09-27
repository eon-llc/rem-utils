#!/bin/bash
#---------------------------------
# SETUP
#---------------------------------
# load variables from config
source "/root/rem-utils/bp-monitor/config.conf"

# full path to config file for convenience
CONFIG_FILE_PATH="${SCRIPT_DIR}/config.conf"

alerts=()
now=$(date -u +"%Y-%m-%dT%H:%M:%SZ")
now_s=$(date -d $now +%s)
now_n=$(date -d $now +%s%N)

#---------------------------------
# SCHEDULE THIS SCRIPT AS CRON
#---------------------------------
if ! crontab -l | grep -q "$SCRIPT_FILE"
then
  (crontab -l ; echo "* * * * * ${SCRIPT_DIR}/${SCRIPT_FILE} >> ${SCRIPT_DIR}/${SCRIPT_LOG_FILE} 2>&1") | crontab -
fi

#---------------------------------
# LOG FILE STATE TEST & MAINTENANCE
#---------------------------------
log_last_modified_s=$(date -r $NODE_LOG_FILE +%s)
modified_diff=$(( $now_s - $log_last_modified_s ))
log_byte_size=$(stat -c%s $NODE_LOG_FILE)

# if log has not been modified
# within the last 5 minutes
if [ $modified_diff -ge 300 ]; then
    alerts+=( "Node log was last modified $(( modified_diff / 60 )) minutes ago" )
fi

# if log is larger than specified threshold
if [ $(( $log_byte_size / 1000000)) -gt $MAX_LOG_SIZE ]; then
    sudo truncate -s 0 $NODE_LOG_FILE
fi

#---------------------------------
# TEST CHAIN STATE
#---------------------------------
# test "remcli get info" response
get_info_response="$(remcli get info)"

# if response is empty or that of failed connection
if [[ -z "${get_info_response// }" ]] || [[ "Failed" =~ ^$get_info_response ]]; then
    alerts+=( "Failed to receive a response from (remcli get info)" )
else
    head_block_num="$(jq '.head_block_num | tonumber' <<< ${get_info_response})"
    li_block_num="$(jq '.last_irreversible_block_num | tonumber' <<< ${get_info_response})"
    block_diff=$(( head_block_num - li_block_num ))

    # if the gap between head block and last irreversible
    # is more than 3 minutes, send an alert
    if (( block_diff / 2 / 60 > 3 )); then
        alerts+=( "Current block is ${block_diff} ahead of last irreversible" )
    fi

    # if last irreversible block has not advanced
    if [ $LAST_IRREVERSIBLE_BLOCK_NUM -eq $li_block_num ]; then
        alerts+=( "Last irreversible block is stuck on ${li_block_num}" )
    fi

    # update last irreversible block number
    sed -i "s/last_irreversible_block_num=.*/last_irreversible_block_num=$li_block_num/" $CONFIG_FILE_PATH
fi

#---------------------------------
# TEST NET PEER STATE
#---------------------------------
# test "remcli net peers" last handshake time
net_peers_response="$(remcli net peers)"

# if response is empty or that of failed connection
if [[ -z "${net_peers_response// }" ]] || [[ "Failed" =~ ^$net_peers_response ]]; then
    alerts+=( "Failed to receive a response from (remcli net peers)" )
else
    last_handshake=$(jq '.[0].last_handshake.time | tonumber' <<< ${net_peers_response})

    # if peer time is older than 3 minutes, in nanoseconds
    if [ $last_handshake -eq 0 ] ; then
        alerts+=( "Peer handshake never took place" )
    fi
fi

#---------------------------------
# SEND ALERTS IF PROBLEMS WERE FOUND
#---------------------------------
# if there are alerts
if [ ${#alerts[@]} -gt 0 ]; then

    # if we haven't sent a message recently
    last_alert_s=$(date -d $LAST_ALERT +%s)
    diff=$(( $now_s - $last_alert_s ))

    # time difference is in seconds
    if [ $diff -ge $(( $ALERT_THRESHOLD * 60 )) ];
    then

        message="\`\`\`Block Producer Alert (${ALERT_THRESHOLD} minute frequency)\n---------------------------------------"

        for i in "${alerts[@]}"
        do
            message="${message}\n- ${i}"
        done

        message="${message}\n---------------------------------------\`\`\`"

        # send alert
        curl -H "Content-Type: application/json" -X POST -d '{"username": "SYSTEM", "content": "'"${message}"'"}' ${DISCORD_CHANNEL}

        # update the timestamp
        sed -i "s/LAST_ALERT=.*/LAST_ALERT=$now/" $CONFIG_FILE_PATH

    fi
fi

#---------------------------------
# SEND DAILY SUMMARY
#---------------------------------
if [ $(date +%H:%M) == $DAILY_STATUS_AT ]; then
    summary="\`\`\`Daily Summary\n---------------------------------------"
    summary="${summary}\nCron job is still running, scheduled to check in at ${DAILY_STATUS_AT} UTC every day."
    summary="${summary}\n---------------------------------------\`\`\`"

    # send summary
    curl -H "Content-Type: application/json" -X POST -d '{"username": "SYSTEM", "content": "'"${summary}"'"}' ${DISCORD_CHANNEL}

    # update the timestamp
    sed -i "s/LAST_STATUS=.*/LAST_STATUS=$now/" $CONFIG_FILE_PATH
fi