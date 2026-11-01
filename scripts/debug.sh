#!/bin/zsh
# Drives a running Claude Buddy from the terminal, for testing.
# Enable once with: defaults write io.github.tooolip.claude-buddy debug -bool true  (then restart the app)
# Usage: scripts/debug.sh state idle|talking|sleeping|dragging|auto
#        scripts/debug.sh input | say "text" | send "message" | hotkey talk|openLast|newChat
#        scripts/debug.sh click-bubble | settings | snapshot /some/dir   (writes pet.png, bubble.png, input.png, state.json)
sock="$HOME/Library/Application Support/ClaudeBuddy/hook.sock"
python3 -c 'import json,sys; print(json.dumps({"debug": sys.argv[1], "arg": sys.argv[2] if len(sys.argv) > 2 else ""}))' "$@" |
  curl -s -m 2 -H 'Expect:' --unix-socket "$sock" --data-binary @- http://localhost/hook
