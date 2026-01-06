#!/bin/bash

# Hardhack Miner Control Script

BASE_URL="http://localhost:8000"

usage() {
    echo "Usage: ./control.sh [start|stop|status|mine|help]"
    echo "  start  : Start the background mining loop"
    echo "  stop   : Stop the background mining loop"
    echo "  status : Check the current miner status"
    echo "  mine   : Run a single benchmark batch (1000 iterations)"
    echo "  help   : Show this help"
}

case "$1" in
    start)
        echo "[*] Starting miner loop..."
        curl -s -X POST "$BASE_URL/start" | python3 -m json.tool
        ;;
    stop)
        echo "[*] Stopping miner loop..."
        curl -s -X POST "$BASE_URL/stop" | python3 -m json.tool
        ;;
    status)
        echo "[*] Miner Status:"
        curl -s "$BASE_URL/" | python3 -m json.tool
        ;;
    mine)
        echo "[*] Running single benchmark (1000 iterations)..."
        curl -s -X POST "$BASE_URL/mine" -d '{"iterations": 1000}'
        echo ""
        ;;
    help|--help|-h)
        usage
        ;;
    *)
        usage
        exit 1
        ;;
esac
