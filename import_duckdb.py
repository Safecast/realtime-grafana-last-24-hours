import duckdb
import os
import json

# Connect to the DuckDB database
conn = duckdb.connect('devices.duckdb')

# Get unique device_urn values from the existing table in the database
device_urns = conn.execute("SELECT DISTINCT device_urn FROM measurements").fetchall()

# Export data for each device_urn to a separate JSON file
for (device_urn,) in device_urns:
    temp_filename = f"/home/rob/Documents/realtime-grafana-last-24-hours/{device_urn.replace(':', '_')}_temp.json"
    final_filename = f"/home/rob/Downloads/JSON/{device_urn.replace(':', '_')}.json"
    
    # Use COPY to create a temporary JSON file
    query = f"""
    COPY (SELECT * FROM measurements WHERE device_urn = '{device_urn}')
    TO '{temp_filename}' (FORMAT JSON);
    """
    conn.execute(query)

    # Read the temporary file and ensure it's valid JSON
    with open(temp_filename, 'r') as temp_file:
        # Read all lines and parse each as JSON
        json_objects = []
        for line in temp_file:
            json_objects.append(json.loads(line.strip()))  # Load each JSON object
        
    # Write the valid JSON data to the final JSON file as an array
    with open(final_filename, 'w') as final_file:
        json.dump(json_objects, final_file)  # Dump as a JSON array

    # Remove the temporary file
    os.remove(temp_filename)

conn.close()
