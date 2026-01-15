#!/bin/bash
# Run multiple miner processes in parallel for maximum throughput

NUM_PROCS=${1:-4}
PYTHON=${PYTHON:-/opt/venv/bin/python3}

echo "Starting $NUM_PROCS parallel miners..."

# Start miners in background
for i in $(seq 1 $NUM_PROCS); do
    $PYTHON miner_fast.py --loop &
    echo "Started miner process $i (PID: $!)"
done

echo "All miners started. Press Ctrl+C to stop."
wait
