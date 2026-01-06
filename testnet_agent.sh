#!/bin/bash

# --- AMADEUS RPC CONFIGURATION ---
RPC_BASE="https://testnet-rpc.ama.one/api/upow"
LOCAL_TEST=${LOCAL_TEST:-false}

MINER_BINARY="./build/hardhack_miner"
OUT_FILE="/tmp/miner_result.json"

echo "==============================================="
echo "   AMADEUS HARD HACK: AUTO-SYNC MINER"
echo "   Target: $RPC_BASE"
echo "==============================================="

if [ ! -f "$MINER_BINARY" ]; then
    echo "[!] Error: Miner binary not found. Build it first."
    exit 1
fi

while true; do
    if [ "$LOCAL_TEST" = "true" ]; then
        SEED_HEX=$(openssl rand -hex 240)
        DIFF=10
    else
        # 1. Fetch current difficulty and epoch from the RPC status
        # We try to grep for difficulty_bits or diff_bits
        STATUS=$(curl -s "https://testnet-rpc.ama.one/api/v1/status")
        DIFF=$(echo "$STATUS" | grep -o '"difficulty_bits":[0-9]*' | cut -d':' -f2)
        
        # Fallback to 20 if status fails or doesn't have it
        if [ -z "$DIFF" ] || [ "$DIFF" -eq 0 ]; then DIFF=20; fi

        # 2. Fetch 240 bytes raw seed
        SEED_HEX=$(curl -s "$RPC_BASE/seed" | xxd -p -c 240 | tr -d '\n')
    fi

    if [ -z "$SEED_HEX" ]; then
        echo "[?] Failed to fetch workload. Retrying..."
        sleep 5
        continue
    fi

    echo "[*] Epoch Active | Diff: $DIFF bits | Seed: ${SEED_HEX:0:16}..."
    
    # Execute miner (iterations 0 = mine until found)
    $MINER_BINARY --seed "$SEED_HEX" --difficulty "$DIFF" --iterations 0 > "$OUT_FILE"
    
    # Parse results
    FOUND_YES=$(grep -c '"found": true' "$OUT_FILE")
    HPS=$(grep -o '"hashes_per_sec": [0-9.]*' "$OUT_FILE" | cut -d' ' -f2)
    SOL_HEX=$(grep -o '"solution_hex": "[^"]*"' "$OUT_FILE" | cut -d'"' -f4)

    if [ "$FOUND_YES" -gt 0 ]; then
        echo -e "\n[SUCCESS] Solution found at $HPS s/s!"
        
        if [ "$LOCAL_TEST" = "false" ]; then
            echo "[*] Submitting to blockchain..."
            # Organizers: submit concat(seed240, tensor_c), final solution should be 1264 bytes
            RESPONSE=$(echo "$SOL_HEX" | xxd -r -p | curl -s -X POST --data-binary @- "$RPC_BASE/validate")
            echo "[+] RPC Response: $RESPONSE"
            
            # If valid_math is true but valid is false, we keep mining on the same seed (nonce logic)
            if echo "$RESPONSE" | grep -q '"valid":true'; then
                echo "[!] SOLUTION ACCEPTED ON CHAIN!"
            fi
        fi
    fi
    
    rm -f "$OUT_FILE"
done