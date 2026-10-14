#!/bin/bash
# Moves everything listed in _move_log.tsv back to its original location.
tail -r "$HOME/2026/_move_log.tsv" | while IFS=$'\t' read -r src dst; do mkdir -p "$(dirname "$src")"; mv "$dst" "$src"; done
