#!/bin/bash

# --- CONFIGURATION (Overrides via Koyeb Env Vars) ---
LOCAL_TEST=${LOCAL_TEST:-true}
COMPETITION_URL=${COMPETITION_URL:-"https://api.managed-testnet.ama.one"}
TESTNET_RPC=${TESTNET_RPC:-"https://testnet.ama.one/"}
API_KEY=${API_KEY:-"your_api_key_here"}
BATCH_SIZE=${BATCH_SIZE:-10000}

MINER_BINARY="./build/hardhack_miner"
PROVER_BINARY="./build/hardhack_prover"

echo "==============================================="
echo "   AMADEUS HARD HACK: KOYEB DEPLOYMENT"
echo "   Mode: $( [ "$LOCAL_TEST" = true ] && echo "LOCAL TEST" || echo "COMPETITION" )"
echo "==============================================="

while true; do
    if [ "$LOCAL_TEST" = true ]; then
        SEED=$(openssl rand -hex 32)
        DIFF=10 
        TYPE="matmul" # Test the miner by default
    else
        WORK=$(curl -s -H "Authorization: Bearer $API_KEY" "$COMPETITION_URL/workload")
        TYPE=$(echo "$WORK" | grep -o '"type":"[^" ]*"' | cut -d'"' -f4)
        SEED=$(echo "$WORK" | grep -o '"seed":"[^" ]*"' | cut -d'"' -f4)
        DIFF=$(echo "$WORK" | grep -o '"difficulty":[0-9]*' | cut -d':' -f2)
    fi

    if [ -z "$TYPE" ] && [ "$LOCAL_TEST" = false ]; then
        echo "[?] Waiting for workload from Admin..."
        sleep 5
        continue
    fi

    if [[ "$TYPE" == "succinct_proof" ]]; then
        echo "[*] Task: Succinct Proof | Seed: ${SEED:0:16}..."
        RESULT=$($PROVER_BINARY --seed "$SEED")
    else
        echo "[*] Task: MatMul Miner | Seed: ${SEED:0:16}..."
        RESULT=$($MINER_BINARY --seed "$SEED" --difficulty "$DIFF" --iterations 0)
    fi

    # Submit result to Admin and Blockchain if not in local test
    if [ "$LOCAL_TEST" = false ]; then
        # 1. Submit to Admin
        curl -s -X POST -H "Content-Type: application/json" \
             -H "Authorization: Bearer $API_KEY" \
             -d "$RESULT" "$COMPETITION_URL/validate"
        
        # 2. Extract solution hex and broadcast to blockchain
        SOL_HEX=$(echo "$RESULT" | sed -n 's/.*"solution_hex":"\([^" ]*\)".*/\1/p')
        if [ ! -z "$SOL_HEX" ]; then
            curl -s -X POST -H "Content-Type: application/json" \
                 -d "{\"jsonrpc\":\"2.0\",\"method\":\"submit_sol\",\"params\":[\"$SOL_HEX\"],\"id\":1}" \
                 "$TESTNET_RPC"
        fi
    else
        echo "[DEBUG] Result: $RESULT"
        sleep 2
    fi
done
