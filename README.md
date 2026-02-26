# Claude Copy

Copy text from Claude Code's terminal UI and paste it clean.

When you select and copy text from Claude Code, your clipboard gets filled with rendering junk: extra margins, box-drawing characters, trailing spaces, and hard line breaks from terminal wrapping. You paste it somewhere and it looks wrong.

claude-copy fixes your clipboard automatically. It runs as a [Hammerspoon](https://www.hammerspoon.org/) key interceptor on macOS, catches `Cmd+C` in terminal apps, and cleans Claude TUI artifacts before you paste.

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

It preserves structure that matters: paragraph breaks, bullet lists, numbered lists, headings, `Key: value` pairs, indented or code-like blocks, and hashtag lines.

## Install

Requires macOS and [Homebrew](https://brew.sh/).

```bash
git clone https://github.com/andersmyrmel/claude-copy.git
cd claude-copy
./install.sh
```

The install script:
1. Installs Hammerspoon if you don't have it
2. Copies `init.lua` and `clean.lua` to `~/.hammerspoon/`
3. Appends a `dofile()` line to your `~/.hammerspoon/init.lua` (won't overwrite existing config)

Then open Hammerspoon, grant it Accessibility permissions when prompted, and reload the config. To update, pull the repo and re-run `./install.sh`.

**Or do it manually:** copy `init.lua` to `~/.hammerspoon/claude-copy.lua` and `clean.lua` to `~/.hammerspoon/clean.lua`, then add `dofile(os.getenv("HOME") .. "/.hammerspoon/claude-copy.lua")` to your `~/.hammerspoon/init.lua`.

## How it works

Pipeline that runs when you press `Cmd+C`:

1. **Intercept** - catches plain `Cmd+C` only when the focused app is a terminal emulator (Ghostty, iTerm2, Terminal, Alacritty, kitty, WezTerm, Hyper, Warp, Rio, Tabby, Wave). Copies from other apps are never touched.
2. **Copy** - sends a real `Cmd+C`, waits for clipboard update, then reads the copied text.
3. **Detect (conservative)** - scores Claude-likeness from multiple signals (2-space margin coverage, `│` markers, diff-like patterns, wrapped-line shape, prompt negatives).
4. **Tiered clean** - high confidence gets strip + rejoin, medium confidence gets strip-only (no reflow), low confidence is left untouched.

## Limitations

- macOS only (Hammerspoon requirement).
- Only plain keyboard `Cmd+C` in terminal apps is intercepted. Menu copy or mouse/context-menu copy is not intercepted.
- Detection is confidence-based and intentionally conservative. Ambiguous text may be strip-only or left untouched.
- Fenced code blocks (triple backtick) get flattened by the terminal's clipboard before our script runs. The terminal copies them as a single line with space padding. Indented code blocks (4+ spaces) are preserved correctly.
- Tested with Ghostty. Should work with iTerm2, Terminal.app, Alacritty, kitty, WezTerm, Hyper, Warp, Rio, Tabby, and Wave.

## Credits

Inspired by [Clean-Clode](https://github.com/TheJoWo/Clean-Clode).

## License

MIT
