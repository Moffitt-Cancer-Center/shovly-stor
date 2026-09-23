# Avro to JSON Converter Script
# This script reads Avro files and converts them to JSON format

import sys
import json
import os
from pathlib import Path

try:
    import fastavro
except ImportError:
    print("ERROR: fastavro library is not installed.")
    print("Please install it using: pip install fastavro")
    sys.exit(1)

def convert_avro_to_json(avro_file_path, json_file_path):
    """Convert an Avro file to JSON format"""
    try:
        records = []
        with open(avro_file_path, 'rb') as avro_file:
            reader = fastavro.reader(avro_file)
            for record in reader:
                records.append(record)
        
        # Write to JSON file
        with open(json_file_path, 'w', encoding='utf-8') as json_file:
            json.dump(records, json_file, indent=2, default=str)
        
        return len(records)
    except Exception as e:
        print(f"ERROR: Failed to convert {avro_file_path}: {str(e)}")
        return -1

def main():
    if len(sys.argv) < 2:
        print("Usage: python ConvertAvroToJson.py <directory_path>")
        sys.exit(1)
    
    directory_path = sys.argv[1]
    
    if not os.path.exists(directory_path):
        print(f"ERROR: Directory not found: {directory_path}")
        sys.exit(1)
    
    # Find all .avro files in the directory
    avro_files = list(Path(directory_path).glob("*.avro"))
    
    if not avro_files:
        print(f"No .avro files found in {directory_path}")
        return
    
    print(f"Found {len(avro_files)} Avro file(s) to convert...")
    print("")
    
    total_records = 0
    converted_count = 0
    
    for avro_file in avro_files:
        json_file = avro_file.with_suffix('.json')
        print(f"Converting: {avro_file.name} -> {json_file.name}")
        
        record_count = convert_avro_to_json(str(avro_file), str(json_file))
        
        if record_count >= 0:
            print(f"  [+] Converted {record_count} records")
            file_size_kb = os.path.getsize(json_file) / 1024
            print(f"  [+] JSON file size: {file_size_kb:.2f} KB")
            total_records += record_count
            converted_count += 1
        else:
            print(f"  [-] Conversion failed")
        
        print("")
    
    print("=" * 60)
    print(f"Conversion Summary:")
    print(f"  Total files converted: {converted_count}/{len(avro_files)}")
    print(f"  Total records: {total_records}")
    print("=" * 60)

if __name__ == "__main__":
    main()
