#!/bin/bash

# --- AMADEUS RPC CONFIGURATION ---
RPC_BASE="https://testnet-rpc.ama.one/api/upow"
LOCAL_TEST=${LOCAL_TEST:-false}

MINER_BINARY="./build/hardhack_miner"
OUT_FILE="/tmp/miner_result.json"

echo "==============================================="
echo "   AMADEUS HARD HACK: FINAL PRODUCTION MINER"
echo "   Mode: $( [ "$LOCAL_TEST" = true ] && echo "LOCAL TEST" || echo "PRODUCTION" )"
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
        # 1. Fetch live difficulty from network
        # Silent fetch, fallback to 10 if missing
        STATUS=$(curl -s "https://testnet-rpc.ama.one/api/v1/status")
        DIFF=$(echo "$STATUS" | grep -o '"difficulty_bits":[0-9]*' | cut -d':' -f2)
        if [ -z "$DIFF" ] || [ "$DIFF" -eq 0 ]; then DIFF=10; fi

        # 2. Fetch 240 bytes raw seed
        SEED_HEX=$(curl -s "$RPC_BASE/seed" | xxd -p -c 240 | tr -d '\n')
    fi

    if [ -z "$SEED_HEX" ]; then
        echo "[?] Waiting for network/seed..."
        sleep 5
        continue
    fi

    echo "[*] Mining... Seed: ${SEED_HEX:0:16} | Diff: $DIFF bits"
    
    # Calculate expected iterations (2^difficulty on average)
    EXPECTED_HASHES=$((1 << DIFF))
    echo "[*] Expected hashes: ~$EXPECTED_HASHES (may take a while for high difficulty)"
    
    # Set timeout based on difficulty (higher difficulty = longer timeout)
    # For diff 20: ~1M hashes expected, timeout after 10 minutes
    # For diff 10: ~1K hashes expected, timeout after 1 minute
    TIMEOUT_SEC=$((DIFF * 30))
    if [ "$TIMEOUT_SEC" -lt 60 ]; then TIMEOUT_SEC=60; fi
    if [ "$TIMEOUT_SEC" -gt 600 ]; then TIMEOUT_SEC=600; fi  # Max 10 minutes
    
    # 3. Execute High-Speed C++ Miner with timeout
    timeout $TIMEOUT_SEC $MINER_BINARY --seed "$SEED_HEX" --difficulty "$DIFF" --iterations 0 > "$OUT_FILE" 2>&1
    TIMEOUT_EXIT=$?
    
    if [ $TIMEOUT_EXIT -eq 124 ]; then
        echo "[!] Mining timeout after ${TIMEOUT_SEC}s (difficulty $DIFF may be too high)"
        echo "[*] Try lowering difficulty or increasing timeout for testing"
    fi
    
    # 4. Parse Results
    FOUND_YES=$(grep -c '"found": true' "$OUT_FILE")
    HPS=$(grep -o '"hashes_per_sec": [0-9.]*' "$OUT_FILE" | cut -d' ' -f2)
    SOL_B58=$(grep -o '"solution_b58": "[^"]*"' "$OUT_FILE" | cut -d'"' -f4)

    if [ "$FOUND_YES" -gt 0 ]; then
        echo -e "\n[SUCCESS] Found Solution! ($HPS s/s)"
        
        if [ "$LOCAL_TEST" = "false" ]; then
            echo "[*] Submitting to blockchain..."
            RESPONSE=$(curl -s "https://testnet-rpc.ama.one/api/upow/validate/$SOL_B58")
            
            # Parse validation response
            VALID=$(echo "$RESPONSE" | grep -o '"valid":[^,}]*' | cut -d':' -f2 | tr -d ' ')
            VALID_MATH=$(echo "$RESPONSE" | grep -o '"valid_math":[^,}]*' | cut -d':' -f2 | tr -d ' ')
            
            # Display the response
            echo "$RESPONSE"
            
            # Show validation status prominently
            if [ "$VALID_MATH" = "true" ]; then
                echo "[✓] Math validation: PASSED"
            elif [ "$VALID_MATH" = "false" ]; then
                echo "[✗] Math validation: FAILED"
            fi
            
            if [ "$VALID" = "true" ]; then
                echo "[✓] Overall validation: PASSED"
            elif [ "$VALID" = "false" ]; then
                echo "[✗] Overall validation: FAILED"
            fi
            echo ""
        else
            echo "[DEBUG] Base58 Solution found (Length: ${#SOL_B58})"
        fi
    fi
    
    rm -f "$OUT_FILE"
done
