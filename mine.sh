#!/bin/bash

# --- CONFIGURATION ---
LOCAL_TEST=${LOCAL_TEST:-false}
RPC_BASE="https://testnet-rpc.ama.one/api/upow"
MINER_BINARY="./build/hardhack_miner"
OUT_FILE="/tmp/miner_result.json"

echo "==============================================="
echo "   AMADEUS HARD HACK: SUB-TRACK A (MINER)"
echo "   Mode: $( [ "$LOCAL_TEST" = true ] && echo "LOCAL TEST" || echo "PRODUCTION" )"
echo "==============================================="

if [ ! -f "$MINER_BINARY" ]; then echo "[!] Error: build first."; exit 1; fi

while true; do
    if [ "$LOCAL_TEST" = true ]; then
        SEED_HEX=$(openssl rand -hex 240)
        DIFF=10
    else
        echo "[*] Fetching workload..."
        SEED_HEX=$(curl -s "$RPC_BASE/seed" | xxd -p -c 240 | tr -d '\n')
        STATUS=$(curl -s "https://testnet-rpc.ama.one/api/v1/status")
        DIFF=$(echo "$STATUS" | grep -o '"difficulty_bits":[0-9]*' | cut -d':' -f2)
        [ -z "$DIFF" ] && DIFF=20
    fi

    echo "[*] Mining... Seed: ${SEED_HEX:0:16} | Diff: $DIFF"
    
    $MINER_BINARY --seed "$SEED_HEX" --difficulty "$DIFF" --iterations 0 > "$OUT_FILE"
    
    HPS=$(grep -o '"hashes_per_sec": [0-9.]*' "$OUT_FILE" | cut -d' ' -f2)
    SOL_B58=$(grep -o '"solution_b58": "[^"]*"' "$OUT_FILE" | cut -d'"' -f4)

    if [ ! -z "$SOL_B58" ]; then
        echo -e "\n[SUCCESS] Found Solution! ($HPS s/s)"
        
        if [ "$LOCAL_TEST" = false ]; then
            echo "[*] Submitting to blockchain via Base58 GET..."
            RESPONSE=$(curl -s "https://testnet-rpc.ama.one/api/upow/validate/$SOL_B58")
            echo "[+] RPC Response: $RESPONSE"
            echo ""
        else
            echo "[DEBUG] Base58 Solution (first 64 chars): ${SOL_B58:0:64}"
        fi
    fi
    rm -f "$OUT_FILE"
done