#!/bin/bash
# HardHack TTNN Miner Script
# Uses Python with TTNN for GPU acceleration

set -e

API_BASE="https://testnet-rpc.ama.one"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "=== HardHack TTNN Miner ==="
echo "Using TTNN GPU acceleration"
echo ""

# Install dependencies if needed
if ! python3 -c "import blake3" 2>/dev/null; then
    echo "Installing blake3..."
    pip3 install blake3 -q
fi

ROUND=1
while true; do
    echo "--- Round $ROUND ---"
    
    # 1. Fetch seed
    SEED_HEX=$(curl -s "$API_BASE/api/upow/seed" | xxd -p -c 240 | tr -d '\n')
    if [ -z "$SEED_HEX" ] || [ ${#SEED_HEX} -ne 480 ]; then
        echo "Error: Failed to fetch seed (got ${#SEED_HEX} hex chars, expected 480)"
        sleep 5
        continue
    fi
    echo "Seed: ${SEED_HEX:0:32}..."
    
    # 2. Fetch difficulty
    STATS=$(curl -s "$API_BASE/api/chain/stats")
    DIFF=$(echo "$STATS" | grep -o '"diff_bits":[0-9]*' | cut -d':' -f2)
    if [ -z "$DIFF" ] || [ "$DIFF" -eq 0 ]; then
        DIFF=20
    fi
    echo "Difficulty: $DIFF bits"
    
    # 3. Mine
    echo "Mining..."
    START=$(date +%s.%N)
    
    RESULT=$(python3 "$SCRIPT_DIR/miner_ttnn.py" --seed "$SEED_HEX" --difficulty "$DIFF" --iterations 0 2>&1)
    
    END=$(date +%s.%N)
    ELAPSED=$(echo "$END - $START" | bc)
    
    # 4. Parse result
    SUCCESS=$(echo "$RESULT" | grep -o '"success": true' || true)
    
    if [ -n "$SUCCESS" ]; then
        SOL_B58=$(echo "$RESULT" | grep -o '"solution_b58": "[^"]*"' | cut -d'"' -f4)
        HASH=$(echo "$RESULT" | grep -o '"hash": "[^"]*"' | cut -d'"' -f4)
        HASHRATE=$(echo "$RESULT" | grep -o '"hashrate": [0-9.]*' | cut -d' ' -f2)
        
        echo "Solution found!"
        echo "  Hash: ${HASH:0:16}..."
        echo "  Time: ${ELAPSED}s"
        echo "  Rate: ${HASHRATE} H/s"
        
        # 5. Submit
        echo "Submitting..."
        RESPONSE=$(curl -s "$API_BASE/api/upow/validate/$SOL_B58")
        echo "Response: $RESPONSE"
        
        VALID=$(echo "$RESPONSE" | grep -o '"valid":true' || true)
        VALID_MATH=$(echo "$RESPONSE" | grep -o '"valid_math":true' || true)
        
        if [ -n "$VALID" ]; then
            echo "✓ VALID SOLUTION ACCEPTED!"
        elif [ -n "$VALID_MATH" ]; then
            echo "✓ Math correct, but solution expired (segment changed)"
        else
            echo "✗ Invalid solution"
        fi
    else
        echo "No solution found in time"
        echo "$RESULT" | tail -5
    fi
    
    echo ""
    ROUND=$((ROUND + 1))
    sleep 1
done
