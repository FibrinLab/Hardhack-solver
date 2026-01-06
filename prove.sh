#!/bin/bash

# --- CONFIGURATION ---
LOCAL_TEST=${LOCAL_TEST:-true}
COMPETITION_URL="https://api.managed-testnet.ama.one"
API_KEY="your_api_key_here"
PROVER_BINARY="./build/hardhack_prover"

echo "==============================================="
echo "   AMADEUS HARD HACK: SUB-TRACK B (PROVER)"
echo "   Mode: $( [ "$LOCAL_TEST" = true ] && echo "LOCAL TEST" || echo "PRODUCTION" )"
echo "==============================================="

if [ ! -f "$PROVER_BINARY" ]; then echo "[!] Error: build first."; exit 1; fi

while true; do
    if [ "$LOCAL_TEST" = true ]; then
        SEED=$(openssl rand -hex 32)
    else
        # Fetch succinct proof task
        WORK=$(curl -s -H "Authorization: Bearer $API_KEY" "$COMPETITION_URL/workload")
        SEED=$(echo "$WORK" | grep -o '"seed":"[^"]*"' | cut -d'"' -f4)
    fi

    if [ ! -z "$SEED" ]; then
        echo "[*] Generating Proof for Seed: ${SEED:0:16}..."
        RESULT=$($PROVER_BINARY --seed "$SEED")
        
        MOPS=$(echo "$RESULT" | grep -o '"throughput_mops": [0-9.]*' | cut -d' ' -f2)
        HASH=$(echo "$RESULT" | grep -o '"proof_hash": "[^"]*"' | cut -d'"' -f4)
        
        echo "[SUCCESS] Proof Hash: $HASH ($MOPS MOPS)"

        if [ "$LOCAL_TEST" = false ]; then
            curl -s -X POST -H "Content-Type: application/json" \
                 -H "Authorization: Bearer $API_KEY" \
                 -d "$RESULT" "$COMPETITION_URL/validate"
        fi
    fi
    
    sleep 2
done
