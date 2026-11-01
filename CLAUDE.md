# Claude Buddy

An always-on-top desktop pet for macOS that talks to Claude Code. Native Swift/AppKit, built as a
Swift package with no Xcode project. Command Line Tools are enough.

## Build and run

```bash
make run        # build release, bundle build/ClaudeBuddy.app, (re)launch it
make install    # same, but installs to ~/Applications (use this copy for "Open at login")
make stop       # quit it
make mem        # RSS, physical footprint and CPU of the running app
make skin       # redraw the built-in skins (Mochi, Aftonsparv) from Tools/make-skin.swift
make hooks      # add the buddy's hooks to ~/.claude/settings.json (merges, backs up first)
make unhooks    # remove them again
```

Launch it with `open`, not by running the binary from a Claude Code shell: a child of a Claude
session inherits `CLAUDE_*` env vars. `ClaudeRunner.environment()` strips those anyway.

## How it works

- `Pet.swift`: borderless non-activating `NSPanel` at floating level on all Spaces. Frames play
  through a discrete `CAKeyframeAnimation` on the sprite layer's `contents`, so the render server
  ticks them and the app isn't woken per frame. The animation is removed while the window is occluded.
- `ClaudeRunner.swift`: `claude -p --output-format stream-json --verbose [--resume <id>]`, with the
  prompt on stdin. Only runs while a reply is generating. Summaries use `claude -p --model haiku`
  with hooks, tools and MCP off, falling back to the first sentence.
- `ChatLinks.swift`: the one place that knows the desktop app's undocumented `claude://` links.
  `claude://resume?session=<cli id>` imports a CLI session into the Code tab and opens it (for a
  session that started in the app, it opens that one). Terminal fallback if the app is missing.
- `HookServer.swift`: unix socket at `~/Library/Application Support/ClaudeBuddy/hook.sock`. The
  hooks from `scripts/hooks.py` curl each event's JSON there. `CLAUDE_BUDDY_CHILD=1` marks claude
  processes the buddy started, and the hook skips them.
- `Hotkeys.swift`: Carbon `RegisterEventHotKey` (no Accessibility permission) plus a recorder
  button for Settings. Defaults: ⌃⌥Space talk, ⌃⌥L open last reply, ⌃⌥N new chat.
  (KeyboardShortcuts was dropped: 2.x needs full Xcode for `#Preview` macros, and SwiftPM looks for
  its resource bundle at the .app root, which breaks code signing.)

Once the buddy's thread has been opened in the desktop app, the next typed message starts a new
thread rather than resuming it from the CLI, so the two never write to the same session at once.

## Skins

A skin is a folder with `manifest.json` and one horizontal PNG strip per state (`idle`, `talking`,
`sleeping`, `dragging`; missing states fall back to idle). See `Skins/default/manifest.json`.
Built-in skins ship in the app's Resources. User skins live in
`~/Library/Application Support/ClaudeBuddy/Skins/`, which gets a `my-skin` copy of the default on
first launch. Pick one in Settings (right-click the pet), along with a size from 50% to 200%.
Frames are resampled at load to the exact pixels they're shown at, so big source sheets don't
cost memory; the built-in ones are drawn at 288px per frame so they stay sharp at 200% on Retina.

## Testing from the terminal

```bash
defaults write io.github.tooolip.claude-buddy debug -bool true   # then restart the app
scripts/debug.sh state sleeping       # force a state (auto to undo)
scripts/debug.sh send "hello"         # send a message as if typed
scripts/debug.sh snapshot /tmp/snap   # pet.png, bubble.png, input.png, state.json
```

To test without spending usage, point `claudePath` at a stand-in script that prints stream-json:
`defaults write io.github.tooolip.claude-buddy claudePath /path/to/fake` (delete the key to undo).

Settings live in the `io.github.tooolip.claude-buddy` defaults domain.
