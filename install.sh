#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
DEST="$HOME/.hammerspoon"

# Install Hammerspoon if missing
if ! brew list --cask hammerspoon &>/dev/null; then
  echo "Installing Hammerspoon..."
  brew install --cask hammerspoon
fi

mkdir -p "$DEST"

# Copy source files into Hammerspoon directory
cp "$SCRIPT_DIR/clean.lua" "$DEST/clean.lua"
cp "$SCRIPT_DIR/init.lua" "$DEST/claude-copy.lua"
echo "Copied claude-copy.lua and clean.lua to $DEST/"

# Append dofile to init.lua (don't overwrite existing config)
if grep -q "claude-copy" "$DEST/init.lua" 2>/dev/null; then
  echo "claude-copy is already in your Hammerspoon config."
else
  echo "" >> "$DEST/init.lua"
  echo "-- claude-copy: auto-clean Claude Code clipboard artifacts" >> "$DEST/init.lua"
  echo "dofile(os.getenv(\"HOME\") .. \"/.hammerspoon/claude-copy.lua\")" >> "$DEST/init.lua"
  echo "Added claude-copy to $DEST/init.lua"
fi

echo "Done. Reload Hammerspoon config to activate."
echo "To update later, pull the repo and re-run this script."
