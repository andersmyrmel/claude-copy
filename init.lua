-- claude-copy: Auto-clean Claude Code clipboard artifacts
-- https://github.com/anthropics/claude-copy
--
-- The Claude Code TUI adds rendering artifacts when you copy text:
--   - Leading 2-space margin
--   - Box-drawing vertical pipes (│)
--   - Trailing whitespace padding
--   - Multi-space padding runs between visual lines
--   - Hard line breaks from terminal width wrapping
--
-- This Hammerspoon script watches your clipboard and fixes all of that.

local cleaningClipboard = false

local function looksLikeClaudeTUI(text)
  local hasBoxChars = text:find("\xe2\x94\x82") ~= nil
  local hasPaddingRuns = text:find("  %s+%S") ~= nil
  local lines = {}
  for line in text:gmatch("[^\n]*") do
    table.insert(lines, line)
  end
  if #lines < 1 then return false end
  local indentedCount = 0
  for _, line in ipairs(lines) do
    if line:match("^  ") then
      indentedCount = indentedCount + 1
    end
  end
  local indentRatio = indentedCount / #lines
  return hasBoxChars or indentRatio > 0.7 or (hasPaddingRuns and indentRatio > 0.3)
end

local function splitPaddedLine(text)
  local segments = {}
  local pos = 1
  while pos <= #text do
    local s, e = text:find("   +", pos)
    if s then
      local seg = text:sub(pos, s - 1)
      if #seg > 0 then table.insert(segments, seg) end
      pos = e + 1
    else
      local seg = text:sub(pos)
      if #seg > 0 then table.insert(segments, seg) end
      break
    end
  end
  return segments
end

local function cleanClaudeTUI(text)
  -- Strip TUI chrome
  local rawLines = {}
  for line in text:gmatch("[^\n]*") do
    line = line:gsub("\xe2\x94\x82", "")
    line = line:gsub("^  ", "")
    line = line:gsub("%s+$", "")
    table.insert(rawLines, line)
  end

  -- Split padding runs (terminal joins visual rows with big space runs)
  local lines = {}
  for _, raw in ipairs(rawLines) do
    if raw == "" then
      table.insert(lines, "")
    else
      local segments = splitPaddedLine(raw)
      for _, seg in ipairs(segments) do
        seg = seg:match("^%s*(.-)%s*$")
        if #seg > 0 then
          table.insert(lines, seg)
        end
      end
    end
  end

  -- Rejoin soft-wrapped lines into paragraphs
  local result = {}
  local i = 1
  while i <= #lines do
    local line = lines[i]
    if line == "" then
      table.insert(result, "")
    else
      local para = line
      while i + 1 <= #lines do
        local nxt = lines[i + 1]
        if nxt == "" then break end
        if nxt:match("^[%-%*%+] ")
          or nxt:match("^%d+%.%s")
          or nxt:match("^#+%s")
          or nxt:match("^%*%*")
          or nxt:match("^%-%-%-")
          or nxt:match("^___")
          or nxt:match("^    ")
          or nxt:match("^\t")
          or nxt:match("^%u[%w_]-:%s")
          or nxt:match("^#%w")
          then break end
        i = i + 1
        para = para .. " " .. nxt
      end
      table.insert(result, para)
    end
    i = i + 1
  end

  return table.concat(result, "\n")
end

clipboardWatcher = hs.pasteboard.watcher.new(function(content)
  if cleaningClipboard then return end
  if type(content) ~= "string" then return end
  if not looksLikeClaudeTUI(content) then return end

  local cleaned = cleanClaudeTUI(content)
  if cleaned == content then return end

  cleaningClipboard = true
  hs.pasteboard.setContents(cleaned)
  cleaningClipboard = false
end)

clipboardWatcher:start()
hs.printf("claude-copy: clipboard cleaner loaded")
