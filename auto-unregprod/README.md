## Auto `unregprod`
Script that monitors last produced block time and unregisters producer in the event of failure to produce.

Clone the repo into your server's root:
```
git clone https://github.com/eon-llc/rem-utils
cd /root/rem-utils/auto-unregprod/
```

Install dependencies:
* [jq](https://stedolan.github.io/jq/) - command line json parser
```
sudo apt-get install jq -y
```

Make script executable:
```
sudo chmod +x auto-unregprod.sh
```

Edit config:
```
nano config.conf
```

Run:
```
./auto-unregprod.sh
```