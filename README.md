# claude-copy

Copy text from Claude Code's terminal UI and paste it clean.

When you select and copy text from Claude Code, your clipboard gets filled with rendering junk: extra margins, box-drawing characters, trailing spaces, and hard line breaks from terminal wrapping. You paste it somewhere and it looks wrong.

claude-copy fixes your clipboard automatically. It runs as a [Hammerspoon](https://www.hammerspoon.org/) watcher on macOS, detects when copied text has TUI artifacts, and cleans it before you paste.

## The problem

Copy this from Claude Code's TUI:

```
  │ I showed this to my uncle who fishes every weekend. His jaw dropped. A pen-sized fishing
  │ rod that extends to a full meter, aluminum alloy, with a reel included. Under a dollar to
  │  source. $21 profit per sale.
```

Paste it somewhere. You get:

```
I showed this to my uncle who fishes every weekend. His jaw dropped. A pen-sized fishing

rod that extends to a full meter, aluminum alloy, with a reel included. Under a dollar to

 source. $21 profit per sale.
```

With claude-copy running, you get:

```
I showed this to my uncle who fishes every weekend. His jaw dropped. A pen-sized fishing rod that extends to a full meter, aluminum alloy, with a reel included. Under a dollar to source. $21 profit per sale.
```

## What it fixes

| Artifact | Example | After |
|----------|---------|-------|
| Leading 2-space margin | `··I showed this` | `I showed this` |
| Box-drawing pipes | `│ some text` | `some text` |
| Trailing whitespace | `some text·······` | `some text` |
| Soft-wrapped line breaks | Line broken at terminal width | Rejoined into paragraph |

It preserves structure that matters: paragraph breaks, bullet lists, numbered lists, headings, `Key: value` pairs, indented code blocks, and hashtag lines.

## Install

Requires macOS and [Homebrew](https://brew.sh/).

```bash
git clone https://github.com/andersmyrmel/claude-copy.git
cd claude-copy
./install.sh
```

The install script:
1. Installs Hammerspoon if you don't have it
2. Appends a `dofile()` line to your `~/.hammerspoon/init.lua` (won't overwrite existing config)

Then open Hammerspoon, grant it Accessibility permissions when prompted, and reload the config.

**Or do it manually:** copy `init.lua` into your `~/.hammerspoon/` directory (or `dofile()` it from your existing config).

## How it works

Pipeline that runs on every clipboard change:

1. **App check** -only runs when the focused app is a terminal emulator (Ghostty, iTerm2, Terminal, Alacritty, kitty, WezTerm, Hyper). Copies from other apps are never touched.
2. **Detect** -checks if 60%+ of lines start with a 2-space indent (Claude Code's TUI margin). Skips text that doesn't match.
3. **Strip** -removes `│` pipes, the 2-space margin, and trailing whitespace. Tracks which lines had extra indentation beyond the margin (code blocks, nested content).
4. **Rejoin** -recombines lines that were soft-wrapped at the terminal width back into paragraphs. Never rejoins indented lines or structural elements (blank lines, list items, headings, etc).

A boolean flag prevents the watcher from re-triggering when it writes the cleaned text back to the clipboard.

## Limitations

- macOS only (Hammerspoon requirement)
- Tested with Ghostty. Supports Ghostty, iTerm2, Terminal.app, Alacritty, kitty, WezTerm, and Hyper.

## Credits

Inspired by [Clean-Clode](https://github.com/TheJoWo/Clean-Clode).

## License

MIT
