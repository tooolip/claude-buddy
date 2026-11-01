#!/usr/bin/env python3
"""Turns a Codex pet spritesheet into a Claude Buddy skin.

Codex pets are one PNG: 8 columns x 9 (or 11) rows of 192x208 cells, one row per state. This
copies the sheet into the user skins folder and writes a manifest that maps Codex's states onto
the buddy's. The sheet itself isn't changed.

Usage: python3 scripts/import-codex-pet.py <spritesheet.png> <skin-id> "<Name>" [--sleep 2,3]

--sleep picks idle-row columns to loop for sleeping (frames with closed eyes look best).
Without it, sleeping plays the idle row slowly.
"""
import argparse
import json
import os
import shutil

SKINS = os.path.expanduser("~/Library/Application Support/ClaudeBuddy/Skins")

# Codex row order and frame timings (ms), from the Codex pets plugin.
ROWS = {
    "idle": [280, 110, 110, 140, 140, 320],
    "running-right": [120, 120, 120, 120, 120, 120, 120, 220],
    "running-left": [120, 120, 120, 120, 120, 120, 120, 220],
    "waving": [140, 140, 140, 280],
    "jumping": [140, 140, 140, 140, 280],
    "failed": [140, 140, 140, 140, 140, 140, 140, 240],
    "waiting": [150, 150, 150, 150, 150, 260],
    "running": [120, 120, 120, 120, 120, 220],
    "review": [150, 150, 150, 150, 150, 280],
}
ROW = {name: i for i, name in enumerate(ROWS)}

# Buddy state -> Codex row. "running" is Codex's "agent is working" pose.
MAPPING = {
    "idle": "idle",
    "talking": "running",
    "dragging": "jumping",
    "draggingLeft": "running-left",
    "draggingRight": "running-right",
    "waving": "waving",
    "failed": "failed",
    "waiting": "waiting",
}


def main():
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("sheet")
    p.add_argument("id")
    p.add_argument("name")
    p.add_argument("--sleep", help="idle-row columns for sleeping, e.g. 2,3")
    args = p.parse_args()

    states = {}
    for buddy, codex in MAPPING.items():
        states[buddy] = {"sheet": "spritesheet.png", "row": ROW[codex], "durations": ROWS[codex]}
    if args.sleep:
        cells = [int(c) for c in args.sleep.split(",")]
        states["sleeping"] = {"sheet": "spritesheet.png", "row": 0, "cells": cells, "durations": [1400] * len(cells)}
    else:
        states["sleeping"] = {"sheet": "spritesheet.png", "row": 0, "durations": [d * 3 for d in ROWS["idle"]]}

    out = os.path.join(SKINS, args.id)
    os.makedirs(out, exist_ok=True)
    shutil.copyfile(args.sheet, os.path.join(out, "spritesheet.png"))
    manifest = {"name": args.name, "frameWidth": 192, "frameHeight": 208, "scale": 2, "states": states}
    with open(os.path.join(out, "manifest.json"), "w") as f:
        json.dump(manifest, f, indent=2)
        f.write("\n")
    print(f"Imported {args.name} to {out}")


if __name__ == "__main__":
    main()
