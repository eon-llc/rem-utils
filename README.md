# REM Utils
 This is a collection of scripts for monitoring and management of REM nodes.

 ## BP Monitor
This `bash` script is designed to monitor node activity and send alerts to [Discord](https://discordapp.com/) via webhook.

While some defaults are provided, settings must be adjusted within `config.conf` prior to first execution. After settings are saved, script needs permission to execute `chmod +x node-monitor.sh` and ran manually once `./node-monitor.sh`. A cron job will be created and further executions will be automatic.

 ## Peer Lists
 A collection of REM chain p2p peers for `testnet` and future `mainnet`. Block Producers who wish to be added should open an issue or submit a pull request.
