# Real-time Grafana Setup for the Last 24 Hours

## Table of Contents

1. [Overview](#overview)
2. [Features](#features)
3. [Prerequisites](#prerequisites)
4. [Installation](#installation)
5. [Usage](#usage)
6. [Configuration](#configuration)
7. [Data Processing Workflow](#data-processing-workflow)
8. [Grafana Setup](#grafana-setup)
9. [Troubleshooting](#troubleshooting)
10. [License](#license)

---

### Overview

This script pulls data from the TTserve server, processes it into JSON files for different Geiger-Müller tube types and air devices, and prepares it for visualization in Grafana. The script is designed to run as a cron job every 5 minutes, filtering out known bad data and retaining only the last 24 hours of measurements.

### Features

- **Automated Data Pulling**: Fetches JSON data every 5 minutes from TTserve.
- **Data Filtering and Segmentation**: Filters data by device types (Geiger-Müller tubes and air devices) and the last 24 hours.
- **Separate JSON Files for Grafana**: Creates individual JSON files for each tube type and air device data for easy integration with Grafana.
- **Database Integration**: Stores processed data in DuckDB for efficient querying and dashboard use.

### Prerequisites

- **Shell Environment**: Requires a Unix-based environment (e.g., Linux) to run the script as a cron job.
- **Python 3.x**: Python is needed for additional data processing.
- **DuckDB**: Used to store and structure data.
- **Grafana**: For visualizing data with the `yesoreyeram-infinity-datasource` plugin.

### Installation

1. **Clone the Repository**:

   ```bash
   git clone https://github.com/yourusername/repo-name.git
   cd repo-name
   ```

2. **Set Up Environment Variables (optional)**:
   Configure environment variables as needed for server access and file paths.

3. **Install Dependencies**:
   - Install DuckDB and required Python packages.
   - Set up the `yesoreyeram-infinity-datasource` in Grafana.

### Usage

The script runs automatically via a cron job but can also be manually triggered as follows:

```bash
./data_pull_script.sh
```

To set up the cron job:

1. Edit the crontab:

   ```bash
   crontab -e
   ```

2. Add the following entry to run the script every 15 minutes:
   ```bash
   */15 * * * * /path/to/data_pull_script.sh
   ```

### Configuration

- **TTserve URL**: Specify the endpoint for pulling data in the script.
- **File Paths**: Adjust paths for where the JSON files are saved on the VPS.
- **Known Bad Data Filtering**: Configure or add filtering conditions as needed.

### Data Processing Workflow

1. **Data Retrieval**: Data is fetched from TTserve, Safecast's gateway, in JSON format.
2. **Data Filtering**: Filters for the last 24 hours of measurements, removing known bad data.
3. **Device Segmentation**:
   - Separates data into JSON files for each Geiger-Müller tube type.
   - Generates a separate JSON file for air devices.
4. **Data Storage**: Stores JSON data on the VPS and DuckDB.
5. **Grafana Integration**: Grafana picks up JSON files as layers, overlaying them on a map for visualization.

### Grafana Setup

- **Datasource**: Configure `yesoreyeram-infinity-datasource` to read from the JSON files.
- **Dashboards**: Use the pre-configured dashboards located in the Dashboards folder to visualize data.

### Troubleshooting

- **Data Not Updating**: Ensure the cron job is running. Check the cron log for any errors.
- **Bad Data Not Filtered**: Review filtering conditions and adjust as necessary.
- **Grafana Not Displaying Data**: Verify that `yesoreyeram-infinity-datasource` is correctly set up and that the JSON file paths are accessible.

### License

This project is licensed under the MIT License. See the LICENSE file for more details.

---

![image(1)](https://github.com/user-attachments/assets/4511bf04-8604-45d6-b5fc-0e79461cf0ab)
![image(2)](https://github.com/user-attachments/assets/03580588-5e55-46e0-84c0-e3b43a09542e)
![image(3)](https://github.com/user-attachments/assets/6095637b-c3a4-40be-a1cd-f331990b159f)
![image(4)](https://github.com/user-attachments/assets/7ec751bd-898d-42bd-9079-e8fc96033aa5)
