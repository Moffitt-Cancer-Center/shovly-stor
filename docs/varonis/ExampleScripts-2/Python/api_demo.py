import os
import json
import datetime
import sys
import argparse
import urllib3
from varonis_api_client import VaronisAPIClient

urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

def get_graphql_files(export_type):
    """Get GraphQL files based on export type"""
    # Define the GraphQL file mappings based on export type
    file_map = {
        "Resources": {
            "Query": "..\Gql\Resources\exportResources.gql",
            "ExportJob": "..\Gql\Common\exportJob.gql",
            "ExportNext": "..\Gql\Common\exportNext.gql"
        }
    }
    
    if export_type not in file_map:
        raise ValueError(f"Unknown export type: {export_type}. Valid types are: {', '.join(file_map.keys())}")
    
    files = file_map[export_type]
    
    # Get the script directory to look for GraphQL files
    script_dir = os.path.dirname(os.path.abspath(__file__))
    
    # Check if files exist and return full paths
    result = {}
    for key, filename in files.items():
        file_path = os.path.join(script_dir, filename)
        if not os.path.exists(file_path):
            raise FileNotFoundError(f"GraphQL file not found: {file_path}")
        result[key] = file_path
    
    return result

def save_results_to_file(results: list, filename: str):
    """Save results to JSON file, converting datetime objects to strings"""
    # Convert datetime objects to strings
    converted_results = convert_datetime_to_string(results)
    
    with open(filename, 'w', encoding='utf-8') as f:
        json.dump(converted_results, f, indent=2, ensure_ascii=False)
    
    print(f"Results saved to {filename}")

def convert_datetime_to_string(obj):
    """Convert datetime objects to ISO format strings for JSON serialization"""
    if isinstance(obj, datetime.datetime):
        return obj.isoformat()
    elif isinstance(obj, datetime.date):
        return obj.isoformat()
    elif isinstance(obj, dict):
        return {key: convert_datetime_to_string(value) for key, value in obj.items()}
    elif isinstance(obj, list):
        return [convert_datetime_to_string(item) for item in obj]
    else:
        return obj    
    
def main():
    parser = argparse.ArgumentParser(description="Varonis API Query Script with GQL")
    parser.add_argument("--config-file", required=True, help="Path to the config file (JSON with domain and api_key)")
    parser.add_argument("--export-type", required=True, choices=["Resources"], help="Type of export to perform")
    parser.add_argument("--data-source-id", type=int, default=2, help="Data source ID for the query")
    args = parser.parse_args()

    try:
        # Get GraphQL files based on export type
        gql_files = get_graphql_files(args.export_type)
        print(f"Using GraphQL files:")
        print(f"  Query: {gql_files['Query']}")
        print(f"  Export Job: {gql_files['ExportJob']}")
        print(f"  Export Next: {gql_files['ExportNext']}")
        
        # Read domain and api_key from config file
        with open(args.config_file, "r", encoding="utf-8") as f:
            config = json.load(f)

        # Build endpoints from domain
        domain = config["domain"]
        endpoint = f"https://{domain}/api/graphql"
        access_token_url = f"https://{domain}/api/authentication/api_keys/token"
        api_key = config["api_key"]

        print(f"Using domain: {domain}")
        print(f"GraphQL endpoint: {endpoint}")
        print(f"Token endpoint: {access_token_url}")

        # Read the GraphQL queries from the files
        with open(gql_files["Query"], "r", encoding="utf-8") as f:
            query = f.read()

        with open(gql_files["ExportJob"], "r", encoding="utf-8") as f:
            export_job = f.read()

        with open(gql_files["ExportNext"], "r", encoding="utf-8") as f:
            export_next = f.read()

        # Initialize the API client
        client = VaronisAPIClient(endpoint, api_key, access_token_url)
        
        print(f"Starting Varonis API query for {args.export_type} export...")
        print(f"Query date: {datetime.datetime.now(datetime.timezone.utc).date()}")
        print(f"Data source ID: {args.data_source_id}")
        
        # Prepare variables for the query
        query_variables = {
            "data_source_id": args.data_source_id
        }
        timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
        base_folder = f"exports_{args.export_type.lower()}_{timestamp}"
        os.makedirs(base_folder, exist_ok=True)

        # Submit query with variables
        job_id = client.submit_query(query, query_variables)
        
        while True:
            # Wait for completion
            jobStatus = client.wait_for_job_completion(export_job, job_id)
            ValidateJobStatus(jobStatus)

            # Generate filename with timestamp
            timestamp = datetime.datetime.now().strftime("%Y%m%d_%H%M%S")
            base_filename = f"{args.export_type.lower()}_result_{timestamp}"
            base_filePath = os.path.join(base_folder, base_filename)
            
            print("Downloading...")
            filenameAvro = f"{base_filePath}.avro"
            raw_results = client.download_results(jobStatus['dataUrl'], filenameAvro)
            
            # Save to JSON
            filenameJson = f"{base_filePath}.json"
            save_results_to_file(raw_results, filenameJson)
            
            print(f"Summary:")
            print(f"- Exported {args.export_type.lower()} count: {len(raw_results)}")

            print(f"Next export cursor: {jobStatus['nextExportCursor']}")
            next_result = client.export_next_async(export_next, jobStatus['nextExportCursor'])
            job_id = next_result['jobId']
        
    except Exception as e:
        print(f"Error: {e}")
        sys.exit(1)

def ValidateJobStatus(jobStatus):           
    if jobStatus['status'] == 'FAILED':
        print("Query failed!")
        sys.exit(1)

    if jobStatus['status'] == 'YIELDED_NO_RESULTS':
        print("Query yielded no results! Ending export")
        sys.exit(0)

if __name__ == "__main__":
    main()