#!/bin/bash
# Keeps serial port open and forwards commands from FIFO to Arduino
# Usage: ./serial_daemon.sh

SCRIPT_DIR="$(dirname "$0")"
FIFO="$SCRIPT_DIR/.serial_fifo"
# Auto-detect serial port (macOS: cu.usbmodem*, Linux/WSL: ttyACM* or ttyUSB*)
if [ -z "$SERIAL_PORT" ]; then
  SERIAL_PORT=$(ls /dev/cu.usbmodem* /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -1)
  if [ -z "$SERIAL_PORT" ]; then
    echo "Error: No Arduino serial port found. Set SERIAL_PORT env var or plug in the Arduino."
    exit 1
  fi
fi
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

# Open FIFO for read+write to prevent EOF when no writers
exec 4<>"$FIFO"

# Read commands from FIFO and forward to Arduino
while read -r cmd <&4; do
  echo -n "$cmd" >&3
done
