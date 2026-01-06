import argparse
import subprocess
import json
import time
import os
import threading
from flask import Flask, jsonify, request

# Configuration
API_BASE_URL = os.environ.get("API_BASE_URL", "http://localhost:8000")
MINER_BINARY = "./build/hardhack_miner"
PORT = int(os.environ.get("PORT", 8000))

app = Flask(__name__)

# Global state for background loop
mining_active = False

def run_miner(iterations):
    """
    Executes the C++ miner binary and captures the output.
    """
    # FIX: Removed "-s" argument as the C++ binary does not support it
    cmd = [MINER_BINARY, "-n", str(iterations), "--json"]
    print(f"[*] Running miner: {" ".join(cmd)}")
    
    try:
        result = subprocess.run(cmd, capture_output=True, text=True, check=True)
        # Parse last line as JSON (in case of other stdout noise)
        lines = result.stdout.strip().split('\n')
        json_line = lines[-1]
        return json.loads(json_line)
    except subprocess.CalledProcessError as e:
        print(f"[!] Miner execution failed: {e}")
        print(f"    Stderr: {e.stderr}")
        return {"error": "Execution failed", "stderr": e.stderr}
    except json.JSONDecodeError as e:
        print(f"[!] Failed to parse miner output: {e}")
        print(f"    Raw output: {result.stdout}")
        return {"error": "JSON parse error", "raw": result.stdout}

def mining_loop():
    global mining_active
    print("[*] Background mining loop started.")
    while mining_active:
        # Mock workload fetch
        iterations = 1000 
        print(f"[*] Processing batch of {iterations}...")
        metrics = run_miner(iterations)
        print(f"[*] Result: {metrics}")
        time.sleep(1)

@app.route('/')
def home():
    return jsonify({
        "status": "online",
        "mining_active": mining_active,
        "endpoints": ["/health", "/mine", "/start", "/stop"]
    })

@app.route('/health')
def health():
    return jsonify({"status": "healthy"}), 200

@app.route('/mine', methods=['POST'])
def mine_once():
    """
    Trigger a single mining run manually.
    """
    data = request.get_json() or {}
    iterations = data.get('iterations', 1000)
    result = run_miner(iterations)
    return jsonify(result)

@app.route('/start', methods=['POST'])
def start_mining():
    global mining_active
    if not mining_active:
        mining_active = True
        thread = threading.Thread(target=mining_loop)
        thread.daemon = True
        thread.start()
        return jsonify({"message": "Mining loop started"})
    return jsonify({"message": "Mining already active"})

@app.route('/stop', methods=['POST'])
def stop_mining():
    global mining_active
    mining_active = False
    return jsonify({"message": "Mining loop stopped"})

if __name__ == "__main__":
    parser = argparse.ArgumentParser()
    parser.add_argument("--server", action="store_true", help="Run as Web Server")
    parser.add_argument("--loop", action="store_true", help="Run immediate loop (CLI mode)")
    args = parser.parse_args()

    if args.server:
        print(f"[*] Starting Web Server on port {PORT}")
        app.run(host='0.0.0.0', port=PORT)
    elif args.loop:
        # CLI Mode
        mining_active = True
        mining_loop()
    else:
        # One-off run
        print(run_miner(1000))