-- claude-copy: Auto-clean Claude Code clipboard artifacts
-- https://github.com/andersmyrmel/claude-copy
--
-- Ghostty (and most terminals) copy Claude Code TUI text as:
--   - 2-space left margin on every line
--   - Newlines at terminal width (soft wraps)
--   - Trailing whitespace padding
--   - Occasionally │ box-drawing pipes
--
-- This Hammerspoon script watches your clipboard and fixes all of that.

local cleaningClipboard = false

local terminalApps = {
  ["Ghostty"] = true,
  ["iTerm2"] = true,
  ["Terminal"] = true,
  ["Alacritty"] = true,
  ["kitty"] = true,
  ["WezTerm"] = true,
  ["Hyper"] = true,
}

local function isTerminalFocused()
  local app = hs.application.frontmostApplication()
  if not app then return false end
  return terminalApps[app:name()] == true
end

local function looksLikeClaudeTUI(text)
  local lines = {}
  for line in text:gmatch("[^\n]*") do
    table.insert(lines, line)
  end
  if #lines < 2 then return false end
  local indentedCount = 0
  for _, line in ipairs(lines) do
    if line:match("^  %S") or line == "" then
      indentedCount = indentedCount + 1
    end
  end
  return indentedCount / #lines > 0.6
end

local function cleanClaudeTUI(text)
  -- Parse lines, tracking which had extra indentation beyond the 2-space margin
  local lines = {}
  for line in text:gmatch("[^\n]*") do
    line = line:gsub("\xe2\x94\x82", "")  -- strip │ if present
    line = line:gsub("%s+$", "")           -- trim trailing whitespace

    -- Check if line has more than the 2-space TUI margin (i.e. content is indented)
    local hasExtraIndent = line:match("^  %s") ~= nil and line:match("%S") ~= nil

    -- Strip the 2-space TUI margin
    line = line:gsub("^  ", "")

    table.insert(lines, { text = line, indented = hasExtraIndent })
  end

  -- Rejoin lines into paragraphs.
  -- Don't rejoin if:
  --   - next line is empty (paragraph break)
  --   - next line was indented beyond the margin (code block, nested content)
  --   - current line was indented beyond the margin
  --   - next line is a structural element (list, heading, key:value, etc)
  local result = {}
  local i = 1
  while i <= #lines do
    local cur = lines[i]
    if cur.text == "" then
      table.insert(result, "")
    elseif cur.indented then
      -- Indented line: keep as-is, don't rejoin
      table.insert(result, cur.text)
    else
      local para = cur.text
      while i + 1 <= #lines do
        local nxt = lines[i + 1]
        if nxt.text == "" then break end
        if nxt.indented then break end
        if nxt.text:match("^[%-%*%+] ")
          or nxt.text:match("^%d+%.%s")
          or nxt.text:match("^#+%s")
          or nxt.text:match("^%*%*")
          or nxt.text:match("^%-%-%-")
          or nxt.text:match("^___")
          or nxt.text:match("^%u[%w_]-:%s")
          or nxt.text:match("^#%w")
          then break end
        i = i + 1
        para = para .. " " .. nxt.text
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
  if not isTerminalFocused() then return end
  if not looksLikeClaudeTUI(content) then return end

  local cleaned = cleanClaudeTUI(content)
  if cleaned == content then return end

  cleaningClipboard = true
  hs.pasteboard.setContents(cleaned)
  cleaningClipboard = false
end)

clipboardWatcher:start()
hs.printf("claude-copy: clipboard cleaner loaded")
