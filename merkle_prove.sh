#!/bin/bash

# --- CONFIGURATION ---
LOCAL_TEST=${LOCAL_TEST:-true}
COMPETITION_URL="https://api.managed-testnet.ama.one"
API_KEY="your_api_key_here"
MERKLE_PROVER_BINARY="./build/hardhack_merkle_prover"
TREE_SIZE=${TREE_SIZE:-1024}

echo "==============================================="
echo "   CHALLENGE B: MERKLE PROOF ON RISC-V"
echo "   Mode: $( [ "$LOCAL_TEST" = true ] && echo "LOCAL TEST" || echo "PRODUCTION" )"
echo "==============================================="

if [ ! -f "$MERKLE_PROVER_BINARY" ]; then 
    echo "[!] Error: Merkle prover binary not found. Build it first."
    exit 1
fi

while true; do
    if [ "$LOCAL_TEST" = "true" ]; then
        SEED=$(openssl rand -hex 32)
        PROOF_INDEX=$((RANDOM % TREE_SIZE))
    else
        # Fetch Merkle proof task
        WORK=$(curl -s -H "Authorization: Bearer $API_KEY" "$COMPETITION_URL/workload")
        SEED=$(echo "$WORK" | grep -o '"seed":"[^"]*"' | cut -d'"' -f4)
        PROOF_INDEX=$(echo "$WORK" | grep -o '"index":[0-9]*' | cut -d':' -f2)
        TREE_SIZE_OPT=$(echo "$WORK" | grep -o '"tree_size":[0-9]*' | cut -d':' -f2)
        if [ ! -z "$TREE_SIZE_OPT" ]; then
            TREE_SIZE=$TREE_SIZE_OPT
        fi
        if [ -z "$PROOF_INDEX" ]; then
            PROOF_INDEX=0
        fi
    fi

    if [ ! -z "$SEED" ]; then
        echo "[*] Generating Merkle Proof... Seed: ${SEED:0:16}... | Tree Size: $TREE_SIZE | Index: $PROOF_INDEX"
        OUTPUT=$($MERKLE_PROVER_BINARY --seed "$SEED" --size "$TREE_SIZE" --index "$PROOF_INDEX" 2>&1)
        
        # Extract JSON line (the line starting with {)
        RESULT=$(echo "$OUTPUT" | grep '^{')
        
        if [ -z "$RESULT" ]; then
            echo "[!] Error: No JSON output found"
            continue
        fi
        
        # Extract metrics
        ROOT_HASH=$(echo "$RESULT" | grep -o '"root_hash": "[^"]*"' | cut -d'"' -f4)
        BUILD_TIME=$(echo "$RESULT" | grep -o '"build_time_ms": [0-9.]*' | cut -d' ' -f2)
        PROOF_TIME=$(echo "$RESULT" | grep -o '"proof_generation_time_ms": [0-9.]*' | cut -d' ' -f2)
        VERIFY_TIME=$(echo "$RESULT" | grep -o '"proof_verification_time_ms": [0-9.]*' | cut -d' ' -f2)
        HASHES_PER_SEC=$(echo "$RESULT" | grep -o '"hashes_per_sec": [0-9]*' | cut -d' ' -f2)
        PROOF_SIZE=$(echo "$RESULT" | grep -o '"proof_size_bytes": [0-9]*' | cut -d' ' -f2)
        STATUS=$(echo "$RESULT" | grep -o '"status": "[^"]*"' | cut -d'"' -f4)
        
        if [ "$STATUS" = "success" ]; then
            echo "[SUCCESS] Root: ${ROOT_HASH:0:16}... | Build: ${BUILD_TIME}ms | Proof: ${PROOF_TIME}ms | Verify: ${VERIFY_TIME}ms"
            echo "[*] Performance: ${HASHES_PER_SEC} hashes/sec | Proof Size: ${PROOF_SIZE} bytes"
            
            if [ "$LOCAL_TEST" = "false" ]; then
                echo "[*] Submitting proof..."
                curl -s -X POST -H "Content-Type: application/json" \
                     -H "Authorization: Bearer $API_KEY" \
                     -d "$RESULT" "$COMPETITION_URL/validate"
            fi
        else
            echo "[!] Error: Proof generation failed"
        fi
    else
        echo "[?] Waiting for workload..."
    fi
    
    sleep 2
done
