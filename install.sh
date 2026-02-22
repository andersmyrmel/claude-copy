#!/bin/bash
set -e

# Install Hammerspoon if missing
if ! brew list --cask hammerspoon &>/dev/null; then
  echo "Installing Hammerspoon..."
  brew install --cask hammerspoon
fi

mkdir -p ~/.hammerspoon

# Append to init.lua (don't overwrite existing config)
if grep -q "claude-copy" ~/.hammerspoon/init.lua 2>/dev/null; then
  echo "claude-copy is already in your Hammerspoon config."
else
  echo "" >> ~/.hammerspoon/init.lua
  echo "-- claude-copy: auto-clean Claude Code clipboard artifacts" >> ~/.hammerspoon/init.lua
  echo "dofile(\"$(pwd)/init.lua\")" >> ~/.hammerspoon/init.lua
  echo "Added claude-copy to ~/.hammerspoon/init.lua"
fi

echo "Done. Reload Hammerspoon config to activate."
