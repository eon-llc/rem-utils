## BP Monitor
This `bash` script is designed to monitor node activity and send alerts to [Discord](https://discordapp.com/) via webhook.

While some defaults are provided, settings must be adjusted within `config.conf` prior to first execution. After settings are saved, script needs permission to execute `chmod +x node-monitor.sh` and ran manually once `./node-monitor.sh`. A cron job will be created and further executions will be automatic.