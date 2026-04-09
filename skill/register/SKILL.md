---
name: register
description: Register current Claude Code session to an agent light LED group (1-4)
---

Register the current session to an LED group for the physical agent light.

The user will provide a group number (1-4) as the argument: $ARGUMENTS

Steps:
1. Find the repo root by locating the closest ancestor directory containing `register.sh`
2. Run the registration script with the group number: `<repo-root>/register.sh $ARGUMENTS`
3. Show the user the output to confirm registration
4. If no argument is provided, show usage: `/register <1-4>`
