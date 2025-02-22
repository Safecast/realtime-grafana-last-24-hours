import duckdb
import os
import json
import concurrent.futures

# Constants
DB_PATH = 'devices.duckdb'
EXPORT_DIR = "/home/grafana.safecast.jp/public_html/JSON"
TEMP_DIR = "/home/grafana.safecast.jp/public_html"

# Ensure export directory exists
os.makedirs(EXPORT_DIR, exist_ok=True)

# Connect to the database
conn = duckdb.connect(DB_PATH, read_only=True)

# Get unique device_urn values
device_urns = [row[0] for row in conn.execute("SELECT DISTINCT device_urn FROM measurements").fetchall() if row[0]]

conn.close()  # Close main connection

def export_device_urn(device_urn):
    """Exports data for a specific device_urn."""
    safe_device_urn = device_urn.replace(':', '_')

    temp_filename = os.path.join(TEMP_DIR, f"{safe_device_urn}_temp.json")
    final_filename = os.path.join(EXPORT_DIR, f"{safe_device_urn}.json")

    try:
        # Connect separately for each task (avoiding concurrent writes)
        conn = duckdb.connect(DB_PATH, read_only=True)

        # Export data directly to a temporary JSON file
        query = f"""
        COPY (SELECT * FROM measurements WHERE device_urn = ?) 
        TO '{temp_filename}' (FORMAT JSON);
        """
        conn.execute(query, [device_urn])

        # Read the temporary file and ensure it's valid JSON
        with open(temp_filename, 'r') as temp_file:
            json_objects = [json.loads(line.strip()) for line in temp_file]

        # Write valid JSON data to final JSON file
        with open(final_filename, 'w') as final_file:
            json.dump(json_objects, final_file)

        # Remove the temporary file
        os.remove(temp_filename)

        conn.close()  # Close connection

    except Exception as e:
        print(f"Error processing {device_urn}: {e}")

# Use ThreadPoolExecutor for parallel processing (CPU-friendly)
with concurrent.futures.ThreadPoolExecutor(max_workers=4) as executor:
    executor.map(export_device_urn, device_urns)

print("All JSON files exported successfully.")
