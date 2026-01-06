#!/bin/bash

# Configuration
MINER_BINARY="./build/hardhack_miner"
DIFFICULTY=10
BATCH_SIZE=10000  # Massive batch size for Stress Test
ITERATIONS=${1:-100} # Default to 100 batches for stress test

echo "==============================================="
echo "   AMADEUS HARD HACK: M4 PRO STRESS TEST"
echo "==============================================="
echo "[*] Cores: $(sysctl -n hw.ncpu) | Batch Size: $BATCH_SIZE"
echo "[*] Target: $ITERATIONS batches"

TOTAL_ITERS=0
TOTAL_MS=0
PEAK_HPS=0

cleanup() {
    echo -e "\n\n================ FINAL RESULTS ================"
    if (( $(echo "$TOTAL_MS > 0" | bc -l) )); then
        SPS=$(echo "scale=2; $TOTAL_ITERS / ($TOTAL_MS / 1000)" | bc)
        echo "Total Nonces Tested: $TOTAL_ITERS"
        echo "Average Throughput:  $SPS solves/sec"
        echo "Peak Throughput:     $PEAK_HPS solves/sec"
    fi
    echo "==============================================="
    exit 0
}

trap cleanup SIGINT

for (( i=1; i<=$ITERATIONS; i++ )); do
    SEED=$(openssl rand -hex 32)
    
    # Run the batch
    RESULT=$($MINER_BINARY --seed "$SEED" --difficulty "$DIFFICULTY" --iterations "$BATCH_SIZE")
    
    # Extract metrics
    HPS=$(echo "$RESULT" | sed -n 's/.*"hashes_per_sec": \([0-9.]*\).*/\1/p')
    ITERS=$(echo "$RESULT" | sed -n 's/.*"iterations": \([0-9.]*\).*/\1/p')
    DUR=$(echo "$RESULT" | sed -n 's/.*"duration_ms": \([0-9.]*\).*/\1/p')
    
    if [ ! -z "$ITERS" ]; then
        TOTAL_ITERS=$((TOTAL_ITERS + ITERS))
        TOTAL_MS=$(echo "$TOTAL_MS + $DUR" | bc)
        
        # Track Peak
        if (( $(echo "$HPS > $PEAK_HPS" | bc -l) )); then
            PEAK_HPS=$HPS
        fi
        
        printf "[Batch %4d/%d] Current: %10.2f s/s | Peak: %10.2f s/s\n" "$i" "$ITERATIONS" "$HPS" "$PEAK_HPS"
    fi
done

cleanup
