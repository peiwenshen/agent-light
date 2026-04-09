# Agent Light

Physical LED status light for Claude Code. Shows what Claude is doing in real-time using an Arduino and LEDs.

```
🔴 Red    = Running (processing / using tools)
🟡 Yellow = Waiting (needs your input / permission)
🟢 Green  = Done (finished responding)
```

Supports up to 4 concurrent sessions, each with its own LED group.

## Hardware

- Arduino UNO R3 (ELEGOO compatible)
- 12x LEDs (4 groups x 3 colors: red, yellow, green)
- 12x 220Ω resistors
- Breadboard + jumper wires

### Wiring

```
Group 1: D4(R)  D3(Y)  D2(G)  → GND
Group 2: D7(R)  D6(Y)  D5(G)  → GND
Group 3: D10(R) D9(Y)  D8(G)  → GND
Group 4: D13(R) D12(Y) D11(G) → GND
```

All LED short legs share a common GND rail.

## Setup

### 1. Clone and enter the repo

```bash
git clone https://github.com/peiwenshen/agent-light.git
cd agent-light
```

### 2. Flash the Arduino

**macOS / Linux:**

```bash
brew install arduino-cli        # macOS
# sudo apt install arduino-cli  # Ubuntu/Debian/WSL
arduino-cli core install arduino:avr
arduino-cli compile --fqbn arduino:avr:uno arduino/agent_light
arduino-cli upload -p $(ls /dev/cu.usbmodem* /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -1) --fqbn arduino:avr:uno arduino/agent_light
```

**WSL note:** WSL does not see USB devices by default. You need [usbipd-win](https://github.com/dorssel/usbipd-win) to attach the Arduino:

```powershell
# In PowerShell (as admin):
winget install usbipd
usbipd list                    # Find the Arduino bus ID
usbipd bind --busid <BUS_ID>
usbipd attach --wsl --busid <BUS_ID>
```

Then in WSL the Arduino appears at `/dev/ttyACM0`.

### 3. Start the serial daemon

The daemon keeps the serial port open so commands are instant (no 2s Arduino reset delay).

```bash
./serial_daemon.sh
# Or run in background:
nohup ./serial_daemon.sh > /dev/null 2>&1 &
```

The serial port is auto-detected. To override: `SERIAL_PORT=/dev/ttyACM0 ./serial_daemon.sh`

### 4. Configure Claude Code hooks

Add hooks to `~/.claude/settings.json` so the light responds to Claude Code events globally (works in any project). If the file already exists, merge the `hooks` key into it.

Replace `AGENT_LIGHT_DIR` below with the **absolute path** to this repo (e.g., `/home/you/agent-light` or `/Users/you/agent-light`).

```json
{
  "hooks": {
    "UserPromptSubmit": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "AGENT_LIGHT_DIR/light.sh running UserPromptSubmit",
            "async": true
          }
        ]
      }
    ],
    "PreToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "AGENT_LIGHT_DIR/light.sh running PreToolUse",
            "async": true
          }
        ]
      }
    ],
    "PostToolUse": [
      {
        "matcher": ".*",
        "hooks": [
          {
            "type": "command",
            "command": "AGENT_LIGHT_DIR/light.sh running PostToolUse",
            "async": true
          }
        ]
      }
    ],
    "Stop": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "AGENT_LIGHT_DIR/light.sh done Stop"
          }
        ]
      }
    ],
    "PermissionRequest": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "AGENT_LIGHT_DIR/light.sh waiting PermissionRequest"
          }
        ]
      }
    ],
    "StopFailure": [
      {
        "hooks": [
          {
            "type": "command",
            "command": "AGENT_LIGHT_DIR/light.sh waiting StopFailure"
          }
        ]
      }
    ]
  }
}
```

### 5. Install the `/register` skill (optional)

```bash
ln -s "$(pwd)/skill/register" ~/.claude/skills/register
```

### 6. Register sessions

Each Claude Code session must be registered to an LED group (1-4). Unregistered sessions are ignored.

In a Claude Code session, send any message first (so the session ID is captured), then:

```
/register 1    # Assign to Group 1
```

Or run the script directly: `./register.sh 1`

## How it works

```
Claude Code hook → light.sh → FIFO → serial_daemon.sh → Arduino → LED
```

1. Claude Code fires a hook event (e.g., `PreToolUse`)
2. `light.sh` reads the `session_id` from stdin JSON, looks up the LED group, and writes a 2-char command (e.g., `1R`) to a named pipe
3. `serial_daemon.sh` forwards the command to the Arduino over USB serial
4. Arduino sets the correct LED in the correct group

## Files

| File | Purpose |
|------|---------|
| `light.sh` | Hook handler — maps events to LED commands |
| `serial_daemon.sh` | Keeps serial port open, forwards FIFO → Arduino |
| `register.sh` | Assigns a session to an LED group |
| `arduino/agent_light/` | Arduino sketch (serial → LED control) |
| `arduino/test_leds/` | Hardware test sketch (cycles all 12 LEDs) |
| `settings.example.json` | Claude Code hook configuration (reference) |
| `skill/register/` | Claude Code `/register` skill |
| `status.sh` | Terminal UI status display (debug) |
| `watch.sh` | Simple log tail (debug) |

## Debugging

Logging is off by default. To enable, set `AGENT_LIGHT_DEBUG=1` in the hook commands (e.g., `AGENT_LIGHT_DEBUG=1 /path/to/light.sh running PreToolUse`).

```bash
# Watch events in real-time (requires debug mode)
tail -f light.log

# Test LEDs manually (while daemon is running)
echo "1R" > .serial_fifo   # Group 1 red
echo "2G" > .serial_fifo   # Group 2 green
echo "3Y" > .serial_fifo   # Group 3 yellow
echo "4O" > .serial_fifo   # Group 4 off
```

## Troubleshooting

**Light stuck on a color:** The `Stop` hook didn't fire (session crashed or timed out). Manually clear it:

```bash
echo "1O" > .serial_fifo   # Replace 1 with your group number
```

**Serial port not found:** Check that the Arduino is plugged in. On WSL, make sure you've attached the USB device with `usbipd`. You can override the port: `SERIAL_PORT=/dev/ttyACM0 ./serial_daemon.sh`

**Commands are slow (2s delay):** The serial daemon isn't running. Start it with `./serial_daemon.sh` — it keeps the port open to avoid Arduino reset delays.
