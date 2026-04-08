#!/bin/bash
# Keeps serial port open and forwards commands from FIFO to Arduino
# Usage: ./serial_daemon.sh

SCRIPT_DIR="$(dirname "$0")"
FIFO="$SCRIPT_DIR/.serial_fifo"
SERIAL_PORT="/dev/cu.usbmodem1101"
PID_FILE="$SCRIPT_DIR/.serial_daemon.pid"

# Cleanup on exit
cleanup() {
  rm -f "$FIFO" "$PID_FILE"
  exec 3>&- 2>/dev/null
  exit 0
}
trap cleanup EXIT INT TERM

# Create FIFO
rm -f "$FIFO"
mkfifo "$FIFO"

# Open serial port (triggers one reset, then stays open)
exec 3>"$SERIAL_PORT"
sleep 2
echo $$ > "$PID_FILE"
echo "Serial daemon ready (PID $$)"

# Read commands from FIFO and forward to Arduino
while true; do
  if read -r cmd < "$FIFO"; then
    echo -n "$cmd" >&3
  fi
done
