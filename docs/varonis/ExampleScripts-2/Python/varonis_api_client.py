import requests
import json
import datetime
import time
from typing import Dict, Any, Optional
import fastavro
from gql import gql, Client
from gql.transport.requests import RequestsHTTPTransport
from gql.transport.exceptions import TransportError


class VaronisAPIClient:
    def __init__(self, endpoint: str, api_key: str, access_token_url: str):
        self.endpoint = endpoint
        self.api_key = api_key
        self.access_token_url = access_token_url
        self.verify_ssl = False
        self.generate_client()

    @property
    def client(self):
        """Property getter that regenerates the client each time it's accessed"""
        return self.generate_client()

    def generate_client(self):
        """Generate a GraphQL client with authentication"""
        self.access_token = self.get_varonis_access_token()

        transport = RequestsHTTPTransport(
            url=self.endpoint,
            headers={
                "Authorization": f"Bearer {self.access_token}",
                "Content-Type": "application/json"
            },
            verify=self.verify_ssl
        )

        return Client(
            transport=transport,
            fetch_schema_from_transport=False
        )

    def get_varonis_access_token(self):
        """Keep the existing token retrieval logic using requests"""
        url = self.access_token_url
        headers = {
            "x-api-key": self.api_key,
            "Content-Type": "application/x-www-form-urlencoded"
        }
        data = {
            "grant_type": "varonis_custom"
        }

        response = requests.post(url, headers=headers, data=data, verify=self.verify_ssl)

        if response.ok:
            return response.json().get("access_token")
        else:
            raise Exception(f"Error: {response.status_code}, {response.text}")
    
    def submit_query(self, query_string: str, variables: Optional[Dict[str, Any]] = None) -> str:
        """Submit a GraphQL query using gql library"""
        try:
            # Parse the query string into a gql Document
            query = gql(query_string)
            
            # Execute the query with variables
            result = self.client.execute(query, variable_values=variables)
            print(f"result = {result}")

            # Dynamic job ID extraction based on response structure
            job_id = None
            if 'resourcesExportAsync' in result:
                job_id = result['resourcesExportAsync']['jobId']
            else:
                raise Exception("Unable to extract job ID from response")

            print(f"Query submitted successfully. Job ID: {job_id}")
            return job_id
            
        except TransportError as e:
            raise Exception(f"Query submission failed: {e}")
        except Exception as e:
            raise Exception(f"GraphQL query error: {e}")

    def check_job_status(self, export_job: str, job_id: str) -> Dict[str, Any]:
        """Check job status using gql library"""        
        try:
            query = gql(export_job)
            result = self.client.execute(query, variable_values={'job_id': job_id})

            job_info = result['exportJob']
            return {
                'status': job_info['jobStatus'],
                'dataUrl': job_info['dataUrl'],
                'hasMoreData': job_info['hasMoreData'],
                'nextExportCursor': job_info['nextExportCursor'],
                'jobId': job_info['jobId']
            }
            
        except TransportError as e:
            raise Exception(f"Status check failed: {e}")
        except Exception as e:
            raise Exception(f"GraphQL status check error: {e}")

    def export_next_async(self, export_next, cursor: str) -> Dict[str, Any]:
        """Export next batch using cursor"""
       
        try:
            query = gql(export_next)
            result = self.client.execute(query, variable_values={'cursor': cursor})

            job_info = result['exportNextAsync']
            return {
                'status': job_info['jobStatus'],
                'dataUrl': job_info['dataUrl'],
                'hasMoreData': job_info['hasMoreData'],
                'nextExportCursor': job_info['nextExportCursor'],
                'jobId': job_info['jobId']
            }
            
        except TransportError as e:
            raise Exception(f"Export next failed: {e}")
        except Exception as e:
            raise Exception(f"GraphQL export next error: {e}")

    def wait_for_job_completion(self, export_job: str, job_id: str, poll_interval: int = 25) -> Dict[str, Any]:
        """Wait for job completion with improved error handling"""

        while True:
            try:
                status_info = self.check_job_status(export_job, job_id)
                status = status_info['status']
                
                if status == 'COMPLETED':
                    print("Job completed successfully!")
                    return status_info
                elif status == 'FAILED':
                    print(f"Job failed")
                    return status_info
                elif status in ['CREATED', 'EXECUTING']:
                    print(f"Job status: {status}")
                    time.sleep(poll_interval)
                elif status in ['YIELDED_NO_RESULTS']:
                    print(f"Job yielded no results")
                    return status_info
                else:
                    print(f"Unexpected job status: {status}")
                    time.sleep(poll_interval)
                    
            except Exception as e:
                print(f"Error checking job status: {e}")
                time.sleep(poll_interval)

    def download_results(self, dataUrl: str, avro_filename: str = "results.avro") -> list:
        """Download Avro results from the provided data URL and return as list of records"""
        try:
            headers = {
                "Authorization": f"Bearer {self.access_token}"
            }
            response = requests.get(dataUrl, verify=False, headers=headers)
            response.raise_for_status()
            # Save to file
            with open(avro_filename, "wb") as f:
                f.write(response.content)
            # Read Avro file
            with open(avro_filename, "rb") as f:
                records = list(fastavro.reader(f))

            print(f"Results saved to {avro_filename}")
            return records
        except requests.RequestException as e:
            raise Exception(f"Results download failed: {e}")
        except Exception as e:
            raise Exception(f"Failed to read Avro file: {e}")




