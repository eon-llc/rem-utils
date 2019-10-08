#!/bin/bash
#---------------------------------
# SETUP
#---------------------------------
# load variables from config
source "/root/rem-utils/node-monitor/config.conf"

alerts=()
messages=()
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
    sed -i "s/last_irreversible_block_num=.*/last_irreversible_block_num=$li_block_num/" $SCRIPT_DIR/$CONFIG_FILE
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
# VOTE AND CLAIM REWARDS
#---------------------------------
if $IS_BP; then

    # unlock wallet
    remcli wallet unlock < /root/walletpass > 2>&1

    # vote every week
    if [ $(date +%A) == $VOTE_DAY ] && [ $(date +%H:%M) == $VOTE_TIME ];then

        # cast votes
        vote_response="$(remcli system voteproducer prods $ACCOUNT_NAME $PRODUCERS_TO_VOTE -p $ACCOUNT_NAME@$PERMISSION_NAME -f)"
        # if vote succeeded
        if [[ "executed transaction" =~ ^$vote_response ]]; then
            messages+=( "Voted for producers: ${PRODUCERS_TO_VOTE}" )
        else
            alerts+=( "Failed to vote for producers" )
        fi
    fi

    # claim every 24 hours
    last_claim_s=$(date -d $LAST_CLAIM +%s)
    claim_diff=$(( $now_s - $last_claim_s ))
    seconds_in_day=$((24 * 60 * 60))

    if [ $claim_diff -gt $seconds_in_day ]; then

        before=$(remcli get currency balance rem.token $ACCOUNT_NAME | sed 's/[^0-9.]*//g')
        claim_response="$(remcli system claimrewards $ACCOUNT_NAME -p $ACCOUNT_NAME@$PERMISSION_NAME -f)"
        after=$(remcli get currency balance rem.token $ACCOUNT_NAME | sed 's/[^0-9.]*//g')
        reward=$(echo "$after - $before" | bc)

        if [ $reward -gt 0 ]; then
            messages+=( "Collected ${reward} REM in rewards" )
        else
            if [[ $claim_response != *"already claimed rewards"* ]]; then
                alerts+=( "Failed to claim rewards" )
            fi
        fi

    fi

fi

#---------------------------------
# SEND ALERTS IF PROBLEMS WERE FOUND
#---------------------------------
# if there are alerts
if [ ${#alerts[@]} -gt 0 ]; then

    # if we haven't sent a message recently
    last_alert_s=$(date -d $LAST_ALERT +%s)
    diff_s=$(( $now_s - $last_alert_s ))

    # time difference is in seconds, alert threshold is in minutes
    if [ $diff_s -ge $(( $ALERT_THRESHOLD * 60 )) ]; then

        alert="\`\`\`Alert (${ALERT_THRESHOLD} minute frequency)\n---------------------------------------"

        for i in "${alerts[@]}"
        do
            alert="${alert}\n- ${i}"
        done

        alert="${alert}\n---------------------------------------\`\`\`"

        # send alert
        curl -H "Content-Type: application/json" -X POST -d '{"username": "'"${NODE_NAME}"'", "content": "'"${alert}"'"}' ${DISCORD_CHANNEL}

        # update the timestamp
        sed -i "s/LAST_ALERT=.*/LAST_ALERT=$now/" $SCRIPT_DIR/$CONFIG_FILE

    fi
fi

#---------------------------------
# SEND DAILY SUMMARY
#---------------------------------
if [ $(date +%H:%M) == $DAILY_STATUS_AT ]; then
    summary="\`\`\`Daily Summary\n---------------------------------------"
    summary="${summary}\nCron job is still running, scheduled to check in at ${DAILY_STATUS_AT} UTC every day."

    for i in "${messages[@]}"
    do
        summary="${summary}\n- ${i}"
    done

    summary="${summary}\n---------------------------------------\`\`\`"

    # send summary
    curl -H "Content-Type: application/json" -X POST -d '{"username": "'"${NODE_NAME}"'", "content": "'"${summary}"'"}' ${DISCORD_CHANNEL}

    # update the timestamp
    sed -i "s/LAST_STATUS=.*/LAST_STATUS=$now/" $SCRIPT_DIR/$CONFIG_FILE
fi