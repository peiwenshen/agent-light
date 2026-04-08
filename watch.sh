#!/bin/bash
# Watch the light status in real-time
# Run this in a separate terminal: ./watch.sh

LOG_FILE="$(dirname "$0")/light.log"
touch "$LOG_FILE"

echo "Watching agent light status... (Ctrl+C to stop)"
echo "---"
tail -f "$LOG_FILE"
