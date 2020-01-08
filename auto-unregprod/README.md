## Auto `unregprod`
Script that monitors last produced block time and unregisters producer in the event of failure to produce.

Clone the repo into your server's root:
```
sudo wget https://github.com/eon-llc/rem-utils
cd /root/rem-utils/auto-unregprod/
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