# ScreenshotToClaude

Hotkey a screen region straight into a [Claude Code](https://claude.com/claude-code) prompt in your terminal.

**Hotkey → drag → type → Enter.** No window switching, no save-then-drag, no
hunting for the file in Finder.

The image arrives in the prompt as `[Image #1]` and is *not* submitted, so you
always get to add context before sending — a screenshot with a question attached
beats a bare screenshot.

## Why this exists

macOS already copies a region to the clipboard with `cmd+ctrl+shift+4`, so the
manual flow is *screenshot → click your terminal → `ctrl+V`*. This collapses
that into one keystroke, and refuses to paste if focus lands somewhere
unexpected.

## Requirements

- macOS
- [Hammerspoon](https://www.hammerspoon.org/) — `brew install --cask hammerspoon`
- Claude Code running in a terminal

## Install

```bash
mkdir -p ~/.hammerspoon/Spoons
git clone https://github.com/iamdanmccarthy/screenshot-to-claude.git
ln -s "$PWD/screenshot-to-claude/ScreenshotToClaude.spoon" ~/.hammerspoon/Spoons/
```

Then in `~/.hammerspoon/init.lua`:

```lua
hs.loadSpoon("ScreenshotToClaude"):bindHotkeys({
  capture = { { "cmd", "shift" }, "2" },
})
```

Reload Hammerspoon's config, and you're done.

### Grant two permissions

1. **Accessibility** — System Settings → Privacy & Security → Accessibility →
   enable Hammerspoon. Needed to focus the window and send the keystroke.
   *Nothing works without this.*
2. **Screen Recording** — macOS prompts the first time you fire the hotkey.
   Needed for `screencapture`. Hammerspoon needs a relaunch after granting it.

## Pick your own hotkey

Any Hammerspoon modifier/key combination works:

```lua
hs.loadSpoon("ScreenshotToClaude"):bindHotkeys({
  capture     = { { "cmd", "shift" }, "pad9" },  -- numeric keypad 9
  captureOnly = { { "cmd", "alt" },   "pad9" },  -- clipboard only, keeps focus
})
```

Key names come from `hs.keycodes.map` — plain characters (`"2"`), keypad keys
(`"pad0"`–`"pad9"`), function keys (`"f13"`), and so on. Run
`hs.inspect(hs.keycodes.map)` in the Hammerspoon console to see them all.

Note that keypad keys only exist on keyboards that have a numeric keypad — a
laptop-only setup should pick something else.

`captureOnly` grabs to the clipboard **without** stealing focus, for collecting
several shots before switching over and pasting them yourself.

## Configuration

Set any of these before or after `bindHotkeys`:

```lua
local s2c = hs.loadSpoon("ScreenshotToClaude")
s2c.terminalApp = "iTerm2"
s2c.saveCopies  = false
s2c:bindHotkeys({ capture = { { "cmd", "shift" }, "2" } })
```

| Variable | Default | What it does |
|---|---|---|
| `terminalApp` | `"Ghostty"` | Terminal app name as macOS reports it — `"iTerm2"`, `"Terminal"`, `"WezTerm"`, `"kitty"`, `"Alacritty"`. |
| `titlePatterns` | `{ "✳" }` | Case-insensitive substrings marking a window as a Claude session. Only consulted when `strictTitleMatch` is `true`. Claude Code prefixes the terminal title with a sparkle; the rest of the title is the live task and changes constantly, so don't match on it. |
| `strictTitleMatch` | `false` | Default pastes into the terminal's active window, whatever its title. Set `true` to only paste into a window matching `titlePatterns` and refuse otherwise — a guard against pasting into a plain shell tab, at the cost of depending on the title being intact. |
| `saveCopies` | `true` | Also write a timestamped PNG, so you can reference the image by path later. |
| `saveDir` | `~/Pictures/claude-screenshots` | Absolute path for saved copies. Created if missing. |
| `pasteMods` / `pasteKey` | `{ "ctrl" }` / `"v"` | The keystroke Claude Code uses to read an image off the clipboard. |
| `pasteDelay` | `0.25` | Seconds to let focus settle before pasting. Raise if pastes occasionally miss. |
| `captureArgs` | `{ "-i", "-c" }` | Arguments to `/usr/sbin/screencapture`. `-c` is required. Add `-o` to drop window shadows. |

## Terminal support

Not Ghostty-specific. The capture and the paste are terminal-agnostic — `ctrl+V`
is Claude Code's own binding for reading a clipboard image, not any terminal's
keybinding. Point `terminalApp` at your terminal and you're done:

```lua
s2c.terminalApp = "iTerm2"
```

The spelling doesn't have to be exact; it's matched with `hs.application.get()`.

The one part that varies by terminal is the `✳` title check, which needs your
terminal to surface the title Claude Code sets. Two cases where it won't:

- **Inside tmux or screen.** The multiplexer intercepts the title escape
  sequence, so the window title reflects tmux rather than Claude Code.
- **Terminals configured to override the title.** Terminal.app and iTerm2 can
  both be set to show their own title instead of the running program's.

Neither affects the default, which ignores titles and pastes into the active
window. They only matter if you opt into `strictTitleMatch = true`.

Verified on Ghostty. Other terminals should work but are untested; reports welcome.

## How it works

1. `screencapture -i -c` grabs an interactive region to the clipboard.
2. The spoon finds the window whose title marks it as a Claude session, and focuses it.
3. It sends `ctrl+V`.

**Why `ctrl+V` and not `cmd+V`:** `cmd+V` goes through the terminal's own
text-paste path, which drops the image. `ctrl+V` is the keystroke Claude Code
itself uses to read an image off the macOS clipboard.

## Gotchas

- **Tab targeting.** The paste lands in whichever tab is active in the target
  window — there's no API for switching tabs, so switch to the tab you want
  first, then hit the hotkey. With `strictTitleMatch = true` the title check
  still can't route *between* tabs in one window; it only tells whether the tab
  you're already on looks like Claude, and refuses if it doesn't.
- **Global hotkeys.** Hammerspoon hotkeys are system-wide and will shadow that
  combination in every app. Pick something you don't otherwise use.
- **Esc during capture** leaves the clipboard untouched. The spoon detects this
  via `hs.pasteboard.changeCount()` and skips the paste, so cancelling never
  pastes a stale image from an hour ago.
- **Focus guard.** If the terminal doesn't come forward, you get an alert and no
  keystroke is sent. It will not fire `ctrl+V` into whatever app happens to be
  frontmost.

## License

MIT
