-- claude-copy: Auto-clean Claude Code clipboard artifacts
-- https://github.com/andersmyrmel/claude-copy
--
-- Intercepts Cmd+C in terminal apps, performs the real copy,
-- then conditionally cleans Claude TUI artifacts in the copied text.

local VERSION = "2026-02-24.2"

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
  minNonEmptyLines = 2,
  minMarginCoverage = 0.65,
  stripOnlyThreshold = 4,
  fullCleanThreshold = 7,
  noPipeFullCleanThreshold = 6,
  noPipeMinWrappedPairsForFull = 2,
  wrapMinLineLength = 24,
  wrapSimilarityDelta = 12,
  wrapJoinSlack = 15,
  wrapMinInferredWidth = 40,
}

-- Full set of keywords that identify a line as code-like.
-- Used by isCodeLikeLine() / startsWithCodeKeyword().
local codeKeywords = {
  "async",
  "await",
  "case",
  "catch",
  "class",
  "const",
  "def",
  "else",
  "elseif",
  "enum",
  "export",
  "finally",
  "for",
  "from",
  "function",
  "if",
  "impl",
  "import",
  "interface",
  "let",
  "local",
  "package",
  "private",
  "protected",
  "public",
  "return",
  "struct",
  "switch",
  "try",
  "type",
  "var",
  "while",
}

-- Subset of codeKeywords used to detect line-number prefixes.
-- Kept tighter to avoid false positives (e.g. "42 else" is ambiguous,
-- "42 const" almost certainly has a line number prefix).
local lineNumberKeywords = {
  "async",
  "await",
  "catch",
  "class",
  "const",
  "def",
  "enum",
  "export",
  "for",
  "function",
  "if",
  "import",
  "interface",
  "let",
  "local",
  "return",
  "struct",
  "try",
  "type",
  "var",
  "while",
}

-- ═══════════════════════════════════════════════════════════════
-- Text Utilities
-- ═══════════════════════════════════════════════════════════════

local function splitLines(text)
  text = text:gsub("\r\n", "\n"):gsub("\r", "\n")
  local lines = {}
  for line in (text .. "\n"):gmatch("(.-)\n") do
    lines[#lines + 1] = line
  end
  if #lines > 0 and lines[#lines] == "" then
    table.remove(lines)
  end
  return lines
end

-- ═══════════════════════════════════════════════════════════════
-- Line Classification
-- ═══════════════════════════════════════════════════════════════

local function isLineNumberPrefixed(line)
  if line:match("^%d+%s%s+%S") then return true end
  local num, rest = line:match("^(%d+)%s+(.+)$")
  if not num or not rest then return false end
  local n = tonumber(num)
  if not n or n < 1 or n > 999 then return false end

  for _, keyword in ipairs(lineNumberKeywords) do
    if rest:match("^" .. keyword .. "%f[%A]") then
      return true
    end
  end
  if rest:match("^//") or rest:match("^/%*") then return true end
  if rest:match("^[%[{(]") then return true end
  if rest:match("^[%a_][%w_]*%s*[%({=:.]") then return true end

  return false
end

local function isStructuralLine(line)
  return line:match("^[%-%*%+] ")
    or line:match("^%d+%.%s")
    or line:match("^%d+%s+[+%-]%s")
    or isLineNumberPrefixed(line)
    or line:match("^#+%s")
    or line:match("^[$#] ")
    or line:match("^%*%*")
    or line:match("^%-%-%-")
    or line:match("^___")
    or line:match("^%u[%w_]-:%s")
    or line:match("^#%w")
end

local function startsWithCodeKeyword(line)
  for _, keyword in ipairs(codeKeywords) do
    if line:match("^%s*" .. keyword .. "%f[%A]") then
      return true
    end
  end
  return false
end

local function isCodeLikeLine(line)
  if not line:match("%S") then return false end
  if line:match("^```") then return true end
  if isLineNumberPrefixed(line) then return true end
  if startsWithCodeKeyword(line) then return true end
  if line:match("^%s*//") or line:match("^%s*/%*") then return true end
  if line:match("^%s*[%{%}%[%]]%s*$") then return true end
  if line:match("^%s*[%w_%.:%[%]\"'`%-]+%s*=%s*[^=]") then return true end
  if line:match("[%{%};]") then return true end
  if line:match("=>") or line:match("::") then return true end
  if line:match("^%s*[%w_%.:]+%b()%s*$") then return true end
  if line:match("^%s*[%w_%.:]+%b()%s*[%{%:]%s*$") then return true end
  return false
end

local function isPromptLike(line)
  return line:match("^[$#] ")
    or line:match("^[%w_.-]+@[%w_.-]+[:~/%w%._%-]*[%$#] ")
    or line:match("^%[[^%]]+%][%$#] ")
end

local function isDiffLikeLine(line)
  return line:match("^@@")
    or line:match("^diff%s+%-%-git")
    or line:match("^index%s+[%w%.]+")
    or line:match("^%-%-%-")
    or line:match("^%+%+%+")
    or line:match("^%d+%s+[+%-]%s")
end

local function parseClaudeLine(rawLine)
  local line = rawLine:gsub("%s+$", "")
  local hasMargin = line:match("^  ") ~= nil and line:match("%S") ~= nil
  local hadPipe = line:match("^  │") ~= nil

  if hasMargin then
    line = line:gsub("^  ", "", 1)
    line = line:gsub("^│ ?", "", 1)
  end

  local nonEmpty = line:match("%S") ~= nil

  return {
    text = line,
    nonEmpty = nonEmpty,
    hasMargin = hasMargin,
    hadPipe = hadPipe,
    indented = line:match("^    %S") ~= nil or line:match("^\t") ~= nil,
    codeLike = isCodeLikeLine(line),
  }
end

-- ═══════════════════════════════════════════════════════════════
-- Flattened Line Recovery
--
-- When the terminal copies numbered code (e.g. diff or editor
-- output), it can collapse multiple visual lines into a single
-- clipboard line. These functions detect and re-split them.
-- ═══════════════════════════════════════════════════════════════

local function collectLineNumberStarts(flat)
  local startsByPos = {}
  local diffStarts = 0

  local function addIfLineStart(pos)
    if pos <= 1 then return end
    if flat:sub(pos - 1, pos - 1):match("%s") then
      startsByPos[pos] = true
    end
  end

  -- Diff-style: "42 + " or "42 - "
  for pos in flat:gmatch("()%d+%s+[+%-]%s") do
    addIfLineStart(pos)
    diffStarts = diffStarts + 1
  end

  -- "42 keyword"
  for _, keyword in ipairs(lineNumberKeywords) do
    for pos, num in flat:gmatch("()(%d+)%s+" .. keyword .. "%f[%A]") do
      if tonumber(num) >= 1 and tonumber(num) <= 999 then
        addIfLineStart(pos)
      end
    end
  end

  -- "42 //" or "42 /*"
  for pos, num in flat:gmatch("()(%d+)%s+//") do
    if tonumber(num) >= 1 and tonumber(num) <= 999 then addIfLineStart(pos) end
  end
  for pos, num in flat:gmatch("()(%d+)%s+/%*") do
    if tonumber(num) >= 1 and tonumber(num) <= 999 then addIfLineStart(pos) end
  end

  -- "42 [", "42 {", "42 ("
  for pos, num in flat:gmatch("()(%d+)%s+[%[{(]") do
    if tonumber(num) >= 1 and tonumber(num) <= 999 then addIfLineStart(pos) end
  end

  -- "42 identifier(" or "42 identifier="
  for pos, num in flat:gmatch("()(%d+)%s+([%a_][%w_]*)([%({=:.])") do
    if tonumber(num) >= 1 and tonumber(num) <= 999 then addIfLineStart(pos) end
  end

  -- Chained line numbers: "42 43 + " (two numbers before diff marker)
  for pos, firstNum, sep in flat:gmatch("()(%d+)(%s+)%d+%s+[+%-]%s") do
    addIfLineStart(pos)
    addIfLineStart(pos + #firstNum + #sep)
  end

  -- Chained: "42 43  X" (two numbers, second followed by double-space + content)
  for pos, firstNum, sep in flat:gmatch("()(%d+)(%s+)%d+%s%s+%S") do
    addIfLineStart(pos)
    addIfLineStart(pos + #firstNum + #sep)
  end

  -- Chained: "42 43 keyword"
  for _, keyword in ipairs(lineNumberKeywords) do
    for pos, firstNum, sep in flat:gmatch("()(%d+)(%s+)%d+%s+" .. keyword .. "%f[%A]") do
      addIfLineStart(pos)
      addIfLineStart(pos + #firstNum + #sep)
    end
  end

  -- "42  X" (number, single space, double-space, content)
  for pos in flat:gmatch("()%d+%s%s+%S") do
    addIfLineStart(pos)
  end

  local starts = {}
  for pos in pairs(startsByPos) do
    starts[#starts + 1] = pos
  end
  table.sort(starts)
  return starts, diffStarts
end

local function hasPlausibleNumberProgression(flat, starts)
  if #starts < 3 then return false end

  local numbers = {}
  for _, pos in ipairs(starts) do
    local num = tonumber(flat:match("^(%d+)", pos))
    if num then numbers[#numbers + 1] = num end
  end
  if #numbers < 3 then return false end

  local plausible = 0
  for i = 2, #numbers do
    local delta = numbers[i] - numbers[i - 1]
    if delta >= 0 and delta <= 25 then
      plausible = plausible + 1
    end
  end

  return plausible >= math.max(2, math.floor((#numbers - 1) * 0.6))
end

local function recoverFlattenedNumberedLine(flat)
  local starts, diffStarts = collectLineNumberStarts(flat)
  if #starts < 3 then return flat end

  if diffStarts < 2 and not hasPlausibleNumberProgression(flat, starts) then
    return flat
  end

  local splitAt = {}
  for _, pos in ipairs(starts) do
    splitAt[pos] = true
  end

  local out = {}
  for i = 1, #flat do
    if splitAt[i] then out[#out + 1] = "\n" end
    out[#out + 1] = flat:sub(i, i)
  end

  local rebuilt = table.concat(out):gsub("^%s*\n", "")

  local normalized = {}
  for _, line in ipairs(splitLines(rebuilt)) do
    local trimmed = line:gsub("^%s+", "")
    if trimmed:match("^%d+%s") then
      normalized[#normalized + 1] = "  " .. trimmed
    else
      normalized[#normalized + 1] = line
    end
  end

  local finalLines = {}
  for _, line in ipairs(normalized) do
    local prefix, num = line:match("^(.-[%]%)};,])%s+(%d+)$")
    local n = tonumber(num)
    if prefix and n and n >= 1 and n <= 999 then
      finalLines[#finalLines + 1] = prefix
      finalLines[#finalLines + 1] = "  " .. tostring(n)
    else
      finalLines[#finalLines + 1] = line
    end
  end

  return table.concat(finalLines, "\n")
end

local function recoverFlattenedNumberedBlock(text)
  local lines = splitLines(text)
  if #lines == 0 then return text end

  local changed = false
  local rebuiltLines = {}
  for _, line in ipairs(lines) do
    local recovered = recoverFlattenedNumberedLine(line)
    if recovered ~= line then changed = true end
    rebuiltLines[#rebuiltLines + 1] = recovered
  end

  if not changed then return text end
  return table.concat(rebuiltLines, "\n")
end

-- ═══════════════════════════════════════════════════════════════
-- Clipboard Classification
--
-- Scores clipboard content on multiple signals to decide:
--   "full"  → strip margins + rejoin wrapped paragraphs
--   "strip" → strip margins only (no reflow)
--   "none"  → leave untouched
-- ═══════════════════════════════════════════════════════════════

local function classifyClaudeClipboard(text)
  local lines = splitLines(text)
  if #lines == 0 then
    return { mode = "none", score = 0 }
  end

  local nonEmpty = 0
  local marginLines = 0
  local pipeLines = 0
  local promptLike = 0
  local diffLike = 0
  local codeLike = 0
  local numberedLines = 0
  local markdownStructural = 0
  local wrappedPairs = 0
  local previousWrapCandidate = nil
  local maxProseLen = 0
  local firstLineNoMargin = false
  local seenFirstNonEmpty = false

  for _, rawLine in ipairs(lines) do
    local parsed = parseClaudeLine(rawLine)

    if parsed.nonEmpty then
      nonEmpty = nonEmpty + 1
      if not seenFirstNonEmpty then
        seenFirstNonEmpty = true
        firstLineNoMargin = not parsed.hasMargin
      end
      if parsed.hasMargin then marginLines = marginLines + 1 end
      if parsed.hadPipe then pipeLines = pipeLines + 1 end
      if isPromptLike(parsed.text) then promptLike = promptLike + 1 end
      if isDiffLikeLine(parsed.text) then diffLike = diffLike + 1 end
      if parsed.codeLike then codeLike = codeLike + 1 end
      if isLineNumberPrefixed(parsed.text) then numberedLines = numberedLines + 1 end
      local t = parsed.text
      if t:match("^%d+%.%s") or t:match("^[%-%*%+] ") or t:match("^#+%s") then
        markdownStructural = markdownStructural + 1
      end

      local isWrapCandidate = not parsed.codeLike
        and not isStructuralLine(parsed.text)
        and not isPromptLike(parsed.text)
        and not isLineNumberPrefixed(parsed.text)
        and not isDiffLikeLine(parsed.text)
        and #parsed.text >= config.wrapMinLineLength

      if isWrapCandidate then
        if #parsed.text > maxProseLen then maxProseLen = #parsed.text end
        if previousWrapCandidate then
          local prevLen = #previousWrapCandidate
          local similarWidth = math.abs(prevLen - #parsed.text) <= config.wrapSimilarityDelta
          local previousLooksWrapped = not previousWrapCandidate:match("[%.%!%?:;]$")
          local previousFillsWidth = maxProseLen > 0 and prevLen >= maxProseLen - 5
          if similarWidth and (previousLooksWrapped or previousFillsWidth) then
            wrappedPairs = wrappedPairs + 1
          end
        end
        previousWrapCandidate = parsed.text
      else
        previousWrapCandidate = nil
      end
    else
      previousWrapCandidate = nil
    end
  end

  if nonEmpty < config.minNonEmptyLines then
    return { mode = "none", score = 0 }
  end

  -- Partial copy: first line has no margin (selection started mid-line),
  -- but remaining lines do. Exclude the first line from coverage calc.
  local partialCopy = firstLineNoMargin and nonEmpty >= 2 and marginLines == (nonEmpty - 1)
  local coverageDenom = partialCopy and (nonEmpty - 1) or nonEmpty
  local marginCoverage = marginLines / coverageDenom
  if marginCoverage < config.minMarginCoverage then
    return { mode = "none", score = 0 }
  end

  if promptLike > 0 and pipeLines == 0 and diffLike == 0 then
    return { mode = "none", score = 0 }
  end

  -- Score: positive signals increase confidence, negative signals decrease.
  local score = 0

  if pipeLines > 0 then score = score + 5 end

  if marginCoverage >= 0.95 then score = score + 3
  elseif marginCoverage >= 0.85 then score = score + 2
  else score = score + 1
  end

  if diffLike >= 2 then score = score + 3
  elseif diffLike == 1 then score = score + 1
  end

  if wrappedPairs >= 3 then score = score + 3
  elseif wrappedPairs >= 2 then score = score + 2
  elseif wrappedPairs == 1 then score = score + 1
  end

  if promptLike > 0 then
    score = score - math.min(4, promptLike * 2)
  end

  if pipeLines == 0 and codeLike == nonEmpty and diffLike == 0 and wrappedPairs == 0 then
    score = score - 3
  end

  if numberedLines >= 2 then score = score + 2 end

  if markdownStructural >= 3 then score = score + 2
  elseif markdownStructural >= 2 then score = score + 1
  end

  if partialCopy then score = score + 1 end
  if marginCoverage < 0.75 then score = score - 1 end

  -- Decide mode from score.
  local mode = "none"
  if pipeLines > 0 then
    if score >= config.fullCleanThreshold then
      mode = "full"
    elseif score >= config.stripOnlyThreshold then
      mode = "strip"
    end
  else
    if numberedLines < 2
      and diffLike == 0
      and score >= config.noPipeFullCleanThreshold
      and wrappedPairs >= config.noPipeMinWrappedPairsForFull
      and codeLike < nonEmpty
    then
      mode = "full"
    elseif marginCoverage >= 0.95
      and codeLike == 0
      and wrappedPairs >= 1
      and numberedLines == 0
      and diffLike == 0
      and promptLike == 0
    then
      mode = "full"
    elseif score >= config.stripOnlyThreshold then
      mode = "strip"
    elseif marginCoverage >= 0.95 then
      mode = "strip"
    end
  end

  return {
    mode = mode,
    score = score,
    nonEmpty = nonEmpty,
    marginCoverage = marginCoverage,
    pipeLines = pipeLines,
    diffLike = diffLike,
    numberedLines = numberedLines,
    markdownStructural = markdownStructural,
    wrappedPairs = wrappedPairs,
  }
end

-- ═══════════════════════════════════════════════════════════════
-- Cleaning
-- ═══════════════════════════════════════════════════════════════

-- Strip uniform minimum indent from contiguous code blocks.
-- Handles extra box padding that some terminals preserve beyond
-- the 2-space margin and pipe character.
local function dedentCodeBlocks(lines)
  local i = 1
  while i <= #lines do
    if lines[i].nonEmpty and (lines[i].codeLike or lines[i].indented) then
      local blockStart = i
      local lastCodeLine = i
      local j = i + 1
      while j <= #lines do
        if lines[j].nonEmpty then
          if lines[j].codeLike or lines[j].indented then
            lastCodeLine = j
          else
            break
          end
        end
        j = j + 1
      end
      local blockEnd = lastCodeLine

      local minIndent = math.huge
      for k = blockStart, blockEnd do
        if lines[k].nonEmpty and not lines[k].text:match("^```") then
          local spaces = lines[k].text:match("^(%s*)")
          if #spaces < minIndent then minIndent = #spaces end
        end
      end

      if minIndent > 0 and minIndent < math.huge then
        for k = blockStart, blockEnd do
          if lines[k].nonEmpty then
            local spaces = lines[k].text:match("^(%s*)")
            if #spaces >= minIndent then
              lines[k].text = lines[k].text:sub(minIndent + 1)
              lines[k].indented = lines[k].text:match("^    %S") ~= nil
                or lines[k].text:match("^\t") ~= nil
            end
          end
        end
      end

      i = blockEnd + 1
    else
      i = i + 1
    end
  end
end

local function inferWrapWidth(lines)
  local maxLen = 0
  for _, parsed in ipairs(lines) do
    if parsed.nonEmpty and not parsed.indented and not parsed.codeLike then
      if #parsed.text > maxLen then maxLen = #parsed.text end
    end
  end
  return maxLen
end

-- Full clean: strip margins, dedent code blocks, rejoin wrapped paragraphs.
local function cleanClaudeTUI(text)
  local lines = {}
  for _, rawLine in ipairs(splitLines(text)) do
    lines[#lines + 1] = parseClaudeLine(rawLine)
  end

  dedentCodeBlocks(lines)
  local wrapWidth = inferWrapWidth(lines)

  local result = {}
  local i = 1
  while i <= #lines do
    local cur = lines[i]

    if not cur.nonEmpty then
      result[#result + 1] = ""
    elseif cur.indented or cur.codeLike then
      result[#result + 1] = cur.text
    else
      local para = cur.text
      local lastLineLen = #cur.text
      while i + 1 <= #lines do
        local nxt = lines[i + 1]
        if not nxt.nonEmpty then break end
        if nxt.indented then break end
        if nxt.codeLike then break end
        if isStructuralLine(nxt.text) then break end
        if wrapWidth >= config.wrapMinInferredWidth
          and lastLineLen < wrapWidth - config.wrapJoinSlack then
          break
        end
        i = i + 1
        local nxtText = nxt.text:match("^%s*(.-)$")
        lastLineLen = #nxtText
        para = para .. " " .. nxtText
      end
      result[#result + 1] = para
    end

    i = i + 1
  end

  return table.concat(result, "\n")
end

-- Strip-only clean: remove margins and stray bare line numbers, no reflow.
local function cleanClaudeTUIStripOnly(text)
  local lines = {}
  for _, rawLine in ipairs(splitLines(text)) do
    lines[#lines + 1] = parseClaudeLine(rawLine)
  end

  dedentCodeBlocks(lines)

  local function isDiffOrNumbered(lineText)
    return isLineNumberPrefixed(lineText) or lineText:match("^%d+%s+[+%-]%s") ~= nil
  end

  local result = {}
  for i, parsed in ipairs(lines) do
    local lineText = parsed.text
    local bareLineNumber = lineText:match("^%d+$") ~= nil

    if bareLineNumber then
      local prev = (lines[i - 1] and lines[i - 1].text) or ""
      local nxt = (lines[i + 1] and lines[i + 1].text) or ""
      if not (isDiffOrNumbered(prev) or isDiffOrNumbered(nxt)) then
        result[#result + 1] = lineText
      end
    else
      result[#result + 1] = lineText
    end
  end

  return table.concat(result, "\n")
end

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
  local normalized = recoverFlattenedNumberedBlock(content)
  local decision = classifyClaudeClipboard(normalized)
  if decision.mode == "none" then return end

  local cleaned
  if decision.mode == "full" then
    cleaned = cleanClaudeTUI(normalized)
  else
    cleaned = cleanClaudeTUIStripOnly(normalized)
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
