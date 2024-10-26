Script for pulling data from TTserver in JSON format and creating spectate JSONs files for different geiger muller tubes. Also Air devices data will be pulled.
The data can be sues in Grafana with a data source called yesoreyeram-infinity-datasource.
Dashboards used are in the folder called Dashboards.

This script runs on a cron job every 5 minutes and pulls the data and safes it as all_devices.json.
The all_devices is filtered on taking only the last 24 hours measurements from TTserve
Some known bad data is filtered out.
From the all_devices 4 files are filtered  for different tube types. 
Also air devices data is is created in a separate file.
