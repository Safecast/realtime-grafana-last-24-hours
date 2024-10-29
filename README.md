Script for pulling data from TTserver in JSON format and creating spectate JSONs files for different geiger muller tubes. Also Air devices data will be pulled.
The data can be sues in Grafana with a data source called yesoreyeram-infinity-datasource.
Dashboards used are in the folder called Dashboards.

This script runs on a cron job every 5 minutes and pulls the data and safes it as all_devices.json.
The all_devices is filtered on taking only the last 24 hours measurements from TTserve
Some known bad data is filtered out.
From the all_devices 4 files are filtered  for different tube types. 
Also air devices data is is created in a separate file.

Data picking up from TTserve (gateway of Safecast)->filtering out last 24-hour data->storing the data on VPS->processing devices by air and tubes-> Grafana picks up the layers and overlay a map->data stored i DuckDB->display on public dashboard. A python script (as part of the main shell script ) extract files with data grouped by devices as JSON files. Those JSON files can be picked up by another Grafana dashboard (work in progress).
![image(1)](https://github.com/user-attachments/assets/4511bf04-8604-45d6-b5fc-0e79461cf0ab)
![image(2)](https://github.com/user-attachments/assets/03580588-5e55-46e0-84c0-e3b43a09542e)
![image(3)](https://github.com/user-attachments/assets/6095637b-c3a4-40be-a1cd-f331990b159f)
![image(4)](https://github.com/user-attachments/assets/7ec751bd-898d-42bd-9079-e8fc96033aa5)
