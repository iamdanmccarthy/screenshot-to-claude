--- === ScreenshotToClaude ===
---
--- Hotkey a screen region straight into a Claude Code prompt in your terminal.
---
--- Press the hotkey, drag a region, and the image lands in the Claude Code
--- prompt as `[Image #1]` — unsubmitted, so you can type your question and hit
--- Enter. No window switching, no save-then-drag.
---
--- Download: https://github.com/iamdanmccarthy/screenshot-to-claude

local obj = {}
obj.__index = obj

obj.name = "ScreenshotToClaude"
obj.version = "1.1.0"
obj.author = "Dan McCarthy"
obj.homepage = "https://github.com/iamdanmccarthy/screenshot-to-claude"
obj.license = "MIT - https://opensource.org/licenses/MIT"

--- ScreenshotToClaude.terminalApp
--- Variable
--- Name of the terminal application running Claude Code. Matched with
--- `hs.application.get()`, so the spelling does not have to be exact.
--- Defaults to `"Ghostty"`. Other values: `"iTerm2"`, `"Terminal"`,
--- `"WezTerm"`, `"kitty"`, `"Alacritty"`.
obj.terminalApp = "Ghostty"

--- ScreenshotToClaude.titlePatterns
--- Variable
--- Case-insensitive substrings that mark a window as a Claude Code session.
--- Defaults to `{ "✳" }` — Claude Code prefixes the terminal title with a
--- sparkle. The rest of the title is the current task and changes constantly,
--- so matching on it is not reliable.
obj.titlePatterns = { "\u{2733}" }

--- ScreenshotToClaude.strictTitleMatch
--- Variable
--- Whether to require a Claude-looking window title before pasting.
---
---  * `false` (default) — paste into the terminal's active window, whatever its
---    title says. Simple and predictable. Use this if you rename tabs, run
---    Claude Code inside tmux, or your terminal overrides the window title.
---  * `true` — only paste into a window whose title matches `titlePatterns`,
---    searching every window of the app and refusing (leaving the screenshot on
---    the clipboard) if none matches. Guards against pasting into a plain shell
---    tab, at the cost of depending on the title being intact.
---
--- Note that a terminal window reports the title of its *active* tab and there
--- is no API for switching tabs, so even in strict mode this cannot route
--- between tabs within one window.
obj.strictTitleMatch = false

--- ScreenshotToClaude.saveCopies
--- Variable
--- Also write each screenshot to `saveDir` as a timestamped PNG, so the same
--- image can be referenced by path later. Defaults to `true`.
obj.saveCopies = true

--- ScreenshotToClaude.saveDir
--- Variable
--- Absolute path for saved copies. Created if missing.
--- Defaults to `~/Pictures/claude-screenshots`.
obj.saveDir = os.getenv("HOME") .. "/Pictures/claude-screenshots"

--- ScreenshotToClaude.pasteMods / ScreenshotToClaude.pasteKey
--- Variable
--- The keystroke that makes Claude Code read an image off the macOS clipboard.
--- Defaults to `{ "ctrl" }` and `"v"`. `cmd+V` goes through the terminal's
--- text-paste path and drops the image, which is why this is ctrl+V.
obj.pasteMods = { "ctrl" }
obj.pasteKey = "v"

--- ScreenshotToClaude.pasteDelay
--- Variable
--- Seconds to let window focus settle before sending the paste keystroke.
--- Defaults to `0.25`. Raise it if pastes occasionally miss.
obj.pasteDelay = 0.25

--- ScreenshotToClaude.captureArgs
--- Variable
--- Arguments passed to `/usr/sbin/screencapture`. Defaults to
--- `{ "-i", "-c" }` — interactive selection, straight to the clipboard.
--- `-c` is required. Add `-o` to drop window shadows in window-capture mode.
obj.captureArgs = { "-i", "-c" }

local SCREENCAPTURE = "/usr/sbin/screencapture"

-- hs.application.get() matches names fuzzily, so `terminalApp` may be spelled
-- differently from the name macOS reports. Compare identity, not spelling.
local function sameApp(a, b)
  if not (a and b) then return false end
  local ida, idb = a:bundleID(), b:bundleID()
  if ida and idb then return ida == idb end
  return a:name() == b:name()
end

local function mkdirp(path)
  local acc = ""
  for segment in path:gmatch("[^/]+") do
    acc = acc .. "/" .. segment
    if not hs.fs.attributes(acc) then hs.fs.mkdir(acc) end
  end
end

function obj:pasteCombo()
  return table.concat(self.pasteMods, "+") .. "+" .. self.pasteKey
end

function obj:findTargetWindow()
  local app = hs.application.get(self.terminalApp)
  if not app then return nil, self.terminalApp .. " is not running" end

  if not self.strictTitleMatch then
    -- Whatever you are looking at in that terminal is the target.
    local win = app:focusedWindow() or app:mainWindow() or app:allWindows()[1]
    if not win then return nil, self.terminalApp .. " has no open windows" end
    return win
  end

  -- Strict: search every window for one whose title marks it as a Claude
  -- session, so a Claude window in the background is still found.
  for _, win in ipairs(app:allWindows()) do
    local title = (win:title() or ""):lower()
    for _, pattern in ipairs(self.titlePatterns) do
      if title:find(pattern:lower(), 1, true) then return win end
    end
  end

  return nil, "no " .. self.terminalApp .. " window looks like a Claude session"
end

function obj:saveCopy(image)
  if not (self.saveCopies and image) then return nil end
  mkdirp(self.saveDir)
  local path = self.saveDir .. "/" .. os.date("%Y%m%d-%H%M%S") .. ".png"
  image:saveToFile(path)
  return path
end

function obj:pasteIntoClaude()
  local win, err = self:findTargetWindow()
  if not win then
    hs.alert.show("Screenshot is on the clipboard — " .. err
      .. "\nSwitch to a Claude session and press " .. self:pasteCombo())
    return self
  end

  local targetApp = win:application()
  local targetName = (targetApp and targetApp:name()) or self.terminalApp

  win:focus()

  hs.timer.doAfter(self.pasteDelay, function()
    -- Never fire the paste blind: if focus did not land where we expected,
    -- leave the shot on the clipboard rather than sending a keystroke into
    -- whatever application happens to be frontmost.
    if not sameApp(hs.application.frontmostApplication(), targetApp) then
      hs.alert.show("Could not focus " .. targetName
        .. " — screenshot is on the clipboard")
      return
    end
    hs.eventtap.keyStroke(self.pasteMods, self.pasteKey)
  end)

  return self
end

--- ScreenshotToClaude:capture([activate])
--- Method
--- Capture an interactive screen selection to the clipboard.
---
--- Parameters:
---  * activate - when `false`, leave the screenshot on the clipboard without
---    stealing focus, for batching several shots. Anything else pastes into
---    Claude Code.
---
--- Returns:
---  * The ScreenshotToClaude object
function obj:capture(activate)
  local before = hs.pasteboard.changeCount()

  hs.task.new(SCREENCAPTURE, function()
    -- The clipboard is the only reliable cancel signal: screencapture's exit
    -- code does not distinguish an Esc cancel across macOS versions. Without
    -- this check, cancelling would paste whatever was on the clipboard before.
    if hs.pasteboard.changeCount() == before then return end

    self:saveCopy(hs.pasteboard.readImage())
    if activate ~= false then self:pasteIntoClaude() end
  end, self.captureArgs):start()

  return self
end

--- ScreenshotToClaude:bindHotkeys(mapping)
--- Method
--- Bind hotkeys for this spoon.
---
--- Parameters:
---  * mapping - a table containing any of:
---    * capture     - capture a region and paste it into Claude Code
---    * captureOnly - capture to the clipboard without stealing focus
---
--- Returns:
---  * The ScreenshotToClaude object
function obj:bindHotkeys(mapping)
  hs.spoons.bindHotkeysToSpec({
    capture = function() self:capture(true) end,
    captureOnly = function() self:capture(false) end,
  }, mapping)
  return self
end

function obj:init()
  return self
end

return obj
