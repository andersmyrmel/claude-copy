-- claude-copy: Auto-clean Claude Code clipboard artifacts
-- https://github.com/andersmyrmel/claude-copy
--
-- Intercepts Cmd+C in terminal apps, performs the real copy,
-- then conditionally cleans Claude TUI artifacts in the copied text.

local VERSION = "2026-02-26"

local scriptDir = debug.getinfo(1, "S").source:match("@(.*/)")
local clean = dofile(scriptDir .. "clean.lua")

-- ═══════════════════════════════════════════════════════════════
-- Configuration
-- ═══════════════════════════════════════════════════════════════

local terminalApps = {
  ["Ghostty"] = true,
  ["iTerm2"] = true,
  ["Terminal"] = true,
  ["Alacritty"] = true,
  ["kitty"] = true,
  ["WezTerm"] = true,
  ["Hyper"] = true,
  ["Warp"] = true,
  ["Rio"] = true,
  ["Tabby"] = true,
  ["Wave"] = true,
}

local config = {
  copyTimeoutMs = 350,
  copyPollIntervalMs = 10,
}

-- ═══════════════════════════════════════════════════════════════
-- Clipboard Interception
-- ═══════════════════════════════════════════════════════════════

local function isTerminalFocused()
  local app = hs.application.frontmostApplication()
  if not app then return false end
  return terminalApps[app:name()] == true
end

local copyInterceptor
local copyInProgress = false

local function triggerRawCopy()
  if copyInterceptor then copyInterceptor:stop() end
  local ok, err = pcall(function()
    hs.eventtap.keyStroke({ "cmd" }, "c", 0)
  end)
  if copyInterceptor then copyInterceptor:start() end

  if not ok then
    hs.printf("claude-copy: failed to send Cmd+C: %s", tostring(err))
    return false
  end
  return true
end

local function readClipboardAfterCopy()
  local startCount = hs.pasteboard.changeCount()
  if not triggerRawCopy() then return nil end

  local waited = 0
  while waited < config.copyTimeoutMs do
    if hs.pasteboard.changeCount() ~= startCount then
      return hs.pasteboard.getContents()
    end
    hs.timer.usleep(config.copyPollIntervalMs * 1000)
    waited = waited + config.copyPollIntervalMs
  end
  return nil
end

local function isPlainCmdC(event)
  if event:getKeyCode() ~= hs.keycodes.map.c then return false end
  local flags = event:getFlags()
  return flags.cmd
    and not flags.shift
    and not flags.alt
    and not flags.ctrl
    and not flags.fn
end

local function handleTerminalCopy()
  local content = readClipboardAfterCopy()
  if type(content) ~= "string" then return end
  local normalized = clean.recoverNumberedBlock(content)
  local decision = clean.classify(normalized)
  if decision.mode == "none" then return end

  local cleaned
  if decision.mode == "full" then
    cleaned = clean.clean(normalized)
  else
    cleaned = clean.stripOnly(normalized)
  end

  if cleaned ~= content then
    hs.pasteboard.setContents(cleaned)
  end
end

copyInterceptor = hs.eventtap.new({ hs.eventtap.event.types.keyDown }, function(event)
  if copyInProgress then return false end
  if not isPlainCmdC(event) then return false end
  if not isTerminalFocused() then return false end

  copyInProgress = true
  hs.timer.doAfter(0, function()
    local ok, err = pcall(handleTerminalCopy)
    if not ok then
      hs.printf("claude-copy: copy handler failed: %s", tostring(err))
    end
    copyInProgress = false
  end)

  return true
end)

copyInterceptor:start()
hs.printf("claude-copy: terminal Cmd+C cleaner loaded (%s)", VERSION)
