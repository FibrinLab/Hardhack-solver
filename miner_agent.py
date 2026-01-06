import argparse
import subprocess
import json
import time
import requests
import os
import sys

# Configuration
API_BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:8000") # Replace with real endpoint
MINER_BINARY = "./build/hardhack_miner"

def get_workload():
    """
    Fetches the next workload from the API.
    Mocks the response for now.
    """
    print(f"[*] Requesting workload from {API_BASE_URL}/workload...")
    try:
        # response = requests.get(f"{API_BASE_URL}/workload")
        # response.raise_for_status()
        # return response.json()
        
        # MOCK RESPONSE
        return {
            "id": "job_12345",
            "matrix_size": 512,
            "iterations": 500,
            "precision": "fp32"
        }
    except Exception as e:
        print(f"[!] Error fetching workload: {e}")
        return None

def submit_result(workload_id, metrics):
    """
    Submits the benchmark result to the API.
    """
    payload = {
        "workload_id": workload_id,
        "metrics": metrics
    }
    print(f"[*] Submitting results for {workload_id}...")
    print(f"    Payload: {json.dumps(payload, indent=2)}")
    
    try:
        # response = requests.post(f"{API_BASE_URL}/submit", json=payload)
        # response.raise_for_status()
        # return response.json()
        
        # MOCK RESPONSE
        return {"status": "accepted", "score": 98.5}
    except Exception as e:
        print(f"[!] Error submitting result: {e}")
        return None

def run_miner(matrix_size, iterations):
    """
    Executes the C++ miner binary and captures the output.
    """
    cmd = [MINER_BINARY, "-s", str(matrix_size), "-n", str(iterations), "--json"]
    print(f"[*] Running miner: {' '.join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        # Parse last line as JSON (in case of other stdout noise)
        lines = result.stdout.strip().split('\n')
        json_line = lines[-1]
        return json.loads(json_line)
    except subprocess.CalledProcessError as e:
        print(f"[!] Miner execution failed: {e}")
        print(f"    Stderr: {e.stderr}")
        return None
    except json.JSONDecodeError as e:
        print(f"[!] Failed to parse miner output: {e}")
        print(f"    Raw output: {result.stdout}")
        return None

def main():
    parser = argparse.ArgumentParser(description="Hard Hack Miner Agent")
    parser.add_argument("--loop", action="store_true", help="Run in a continuous loop")
    args = parser.parse_args()

    while True:
        workload = get_workload()
        if not workload:
            print("[!] No workload received. Retrying in 5s...")
            time.sleep(5)
            continue

        print(f"[*] Received Workload: {workload['id']} (Size: {workload['matrix_size']}x{workload['matrix_size']})")
        
        metrics = run_miner(workload['matrix_size'], workload['iterations'])
        
        if metrics:
            result = submit_result(workload['id'], metrics)
            if result:
                print(f"[*] Submission accepted! Score: {result.get('score')}")
        
        if not args.loop:
            break
        
        time.sleep(1)

if __name__ == "__main__":
    main()
