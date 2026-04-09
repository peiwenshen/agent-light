# Agent Light

Physical LED status light for Claude Code. Shows what Claude is doing in real-time using an Arduino UNO and LEDs.

```
🔴 Red    = Running (processing / using tools)
🟡 Yellow = Waiting (needs your input / permission)
🟢 Green  = Done (finished responding)
```

Supports up to 4 concurrent sessions, each with its own LED group.

## Hardware

- Arduino UNO R3 (ELEGOO compatible)
- 12x LEDs (4 groups × 3 colors: red, yellow, green)
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

### 1. Flash the Arduino

```bash
brew install arduino-cli
arduino-cli core install arduino:avr
arduino-cli compile --fqbn arduino:avr:uno arduino/agent_light
arduino-cli upload -p /dev/cu.usbmodem1101 --fqbn arduino:avr:uno arduino/agent_light
```

### 2. Configure Claude Code hooks

Copy the hook config into your Claude Code settings:

```bash
cat settings.example.json
# Copy the "hooks" section into ~/.claude/settings.json
```

### 3. Start the serial daemon

The daemon keeps the serial port open so commands are instant (no 2s Arduino reset delay).

```bash
./serial_daemon.sh
# Or run in background:
nohup ./serial_daemon.sh > /dev/null 2>&1 &
```

### 4. Register sessions

Each Claude Code session can be assigned to an LED group (1-4):

```bash
# In Claude Code session A, send any message first, then:
./register.sh 1    # Assign to Group 1

# In Claude Code session B, send any message first, then:
./register.sh 2    # Assign to Group 2
```

Unregistered sessions default to Group 1.

## How it works

```
Claude Code hook → light.sh → FIFO → serial_daemon.sh → Arduino → LED
```

1. Claude Code fires a hook event (e.g. `PreToolUse`)
2. `light.sh` reads the `session_id` from stdin JSON, looks up the LED group, and writes a 2-char command (e.g. `1R`) to a named pipe
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
| `settings.example.json` | Claude Code hook configuration |
| `status.sh` | Terminal UI status display |
| `watch.sh` | Simple log tail |

## Skill (optional)

A Claude Code skill is included so you can register sessions with `/register <1-4>` instead of running the script manually.

To install, symlink it into your skills directory:

```bash
ln -s "$(pwd)/skill/register" ~/.claude/skills/register
```

## Debugging

```bash
# Watch events in real-time
tail -f light.log

# Test LEDs manually (while daemon is running)
echo "1R" > .serial_fifo   # Group 1 red
echo "2G" > .serial_fifo   # Group 2 green
echo "3Y" > .serial_fifo   # Group 3 yellow
echo "4O" > .serial_fifo   # Group 4 off
```
