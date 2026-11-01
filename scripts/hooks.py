#!/usr/bin/env python3
"""Adds or removes Claude Buddy's hooks in ~/.claude/settings.json.

The hooks pipe each event's JSON to the buddy's unix socket, so the pet reacts to every
Claude Code session (desktop app ones included). It merges into existing settings, leaves
other hooks alone, and backs the file up before writing.

Usage: python3 scripts/hooks.py install | uninstall | status
"""
import json
import os
import shutil
import sys
import time

SETTINGS = os.path.expanduser("~/.claude/settings.json")
EVENTS = ["UserPromptSubmit", "Stop", "StopFailure", "Notification"]
MARK = "# claude-buddy"
# Skips events from claude processes the buddy started itself; never blocks or fails Claude.
COMMAND = (
    '[ -n "$CLAUDE_BUDDY_CHILD" ] || curl -s -m 2 -H \'Expect:\' '
    '--unix-socket "$HOME/Library/Application Support/ClaudeBuddy/hook.sock" '
    "--data-binary @- http://localhost/hook >/dev/null 2>&1; true " + MARK
)


def is_ours(group):
    return any(MARK in h.get("command", "") for h in group.get("hooks", []))


def load():
    if not os.path.exists(SETTINGS):
        return {}
    with open(SETTINGS) as f:
        return json.load(f)


def save(settings):
    if os.path.exists(SETTINGS):
        backup = f"{SETTINGS}.bak-claude-buddy-{time.strftime('%Y%m%d-%H%M%S')}"
        shutil.copy2(SETTINGS, backup)
        print(f"Backed up to {backup}")
    os.makedirs(os.path.dirname(SETTINGS), exist_ok=True)
    tmp = SETTINGS + ".tmp"
    with open(tmp, "w") as f:
        json.dump(settings, f, indent=2, ensure_ascii=False)
        f.write("\n")
    os.replace(tmp, SETTINGS)


def strip(settings):
    hooks = settings.get("hooks", {})
    for event in EVENTS:
        groups = [g for g in hooks.get(event, []) if not is_ours(g)]
        if groups:
            hooks[event] = groups
        else:
            hooks.pop(event, None)
    if "hooks" in settings and not hooks:
        del settings["hooks"]


def installed(settings):
    hooks = settings.get("hooks", {})
    return [e for e in EVENTS if any(is_ours(g) for g in hooks.get(e, []))]


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else "status"
    settings = load()
    if cmd == "install":
        strip(settings)
        hooks = settings.setdefault("hooks", {})
        for event in EVENTS:
            hooks.setdefault(event, []).append({"hooks": [{"type": "command", "command": COMMAND, "timeout": 5}]})
        save(settings)
        print("Installed Claude Buddy hooks for: " + ", ".join(EVENTS))
        print("Open sessions pick them up on their next prompt.")
    elif cmd == "uninstall":
        if not installed(settings):
            print("No Claude Buddy hooks to remove.")
            return
        strip(settings)
        save(settings)
        print("Removed Claude Buddy hooks.")
    elif cmd == "status":
        found = installed(settings)
        print("Installed for: " + ", ".join(found) if found else "Not installed.")
    else:
        sys.exit(__doc__)


if __name__ == "__main__":
    main()
