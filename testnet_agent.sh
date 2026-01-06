#!/bin/bash

# --- CONFIGURATION ---
LOCAL_TEST=true

COMPETITION_URL="https://api.managed-testnet.ama.one"
TESTNET_RPC="https://testnet.ama.one/"
API_KEY="your_api_key_here"

MINER_BINARY="./build/hardhack_miner"
PROVER_BINARY="./build/hardhack_prover"

echo "==============================================="
echo "   AMADEUS HARD HACK: DUAL-TRACK AGENT"
echo "==============================================="

TASK_TOGGLE=0

while true; do
    if [ "$LOCAL_TEST" = true ]; then
        SEED=$(openssl rand -hex 32)
        DIFF=10 
        if [ $((TASK_TOGGLE % 2)) -eq 0 ]; then TYPE="matmul"; else TYPE="succinct_proof"; fi
        TASK_TOGGLE=$((TASK_TOGGLE + 1))
    else
        WORK=$(curl -s -H "Authorization: Bearer $API_KEY" "$COMPETITION_URL/workload")
        TYPE=$(echo "$WORK" | grep -o '"type":"[^"]*"' | cut -d'"' -f4)
        SEED=$(echo "$WORK" | grep -o '"seed":"[^"]*"' | cut -d'"' -f4)
        DIFF=$(echo "$WORK" | grep -o '"difficulty":[0-9]*' | cut -d':' -f2)
    fi

    if [[ "$TYPE" == "succinct_proof" ]]; then
        echo "[*] Task: Sub-Track B (Succinct Proof) | Seed: ${SEED:0:16}..."
        RESULT=$($PROVER_BINARY --seed "$SEED")
        HASH=$(echo "$RESULT" | sed -n 's/.*"proof_hash":[ ]*"\([^"]*\)".*/\1/p')
        echo "[+] Proof Hash Found: $HASH"
    else
        echo "[*] Task: Sub-Track A (MatMul Miner) | Seed: ${SEED:0:16}..."
        RESULT=$($MINER_BINARY --seed "$SEED" --difficulty "$DIFF" --iterations 0)
        
        HPS=$(echo "$RESULT" | sed -n 's/.*"hashes_per_sec":[ ]*\([0-9.]*\).*/\1/p')
        SOL=$(echo "$RESULT" | sed -n 's/.*"solution_hex":[ ]*"\([^"]*\)".*/\1/p')
        
        echo "[SUCCESS] Found solution! ($HPS solves/sec)"
        echo "[+] Solution Hex: ${SOL:0:64}..."
    fi

    if [ "$LOCAL_TEST" = false ]; then
        curl -s -X POST -H "Content-Type: application/json" \
             -H "Authorization: Bearer $API_KEY" \
             -d "$RESULT" "$COMPETITION_URL/validate"
    else
        echo "-----------------------------------------------"
        sleep 2
    fi
done