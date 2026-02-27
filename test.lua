#!/usr/bin/env lua
-- Tests for claude-copy/clean.lua
-- Run: lua test.lua

local clean = dofile("clean.lua")

local passed, failed = 0, 0

local function test(name, fn)
  local ok, err = pcall(fn)
  if ok then
    passed = passed + 1
  else
    failed = failed + 1
    io.write("FAIL: " .. name .. "\n  " .. tostring(err) .. "\n")
  end
end

local function eq(got, expected, msg)
  if got ~= expected then
    error((msg or "") .. "\n  expected: " .. tostring(expected) .. "\n       got: " .. tostring(got))
  end
end

-- Helper: simulate raw clipboard with 2-space margin on each line.
local function margin(lines)
  local out = {}
  for _, l in ipairs(lines) do
    out[#out + 1] = "  " .. l
  end
  return table.concat(out, "\n")
end

-- Helper: simulate raw clipboard with 2-space margin + pipe on each line.
local function piped(lines)
  local out = {}
  for _, l in ipairs(lines) do
    out[#out + 1] = "  │ " .. l
  end
  return table.concat(out, "\n")
end

-- ═══════════════════════════════════════════════════════════════
-- Classification
-- ═══════════════════════════════════════════════════════════════

test("classify: piped prose → full", function()
  local input = piped({
    "This is a long line of text that wraps at the terminal width and keeps on going until",
    "it reaches the end of the paragraph and finishes here.",
  })
  local r = clean.classify(input)
  eq(r.mode, "full")
end)

test("classify: margined prose → full (high coverage, no code)", function()
  local input = margin({
    "This is a long line of text that wraps at the terminal width and keeps on going until",
    "it reaches the end of the paragraph and finishes here with more text added for width.",
  })
  local r = clean.classify(input)
  eq(r.mode, "full")
end)

test("classify: no margin → none", function()
  local input = "just plain text\nwith no margin at all"
  local r = clean.classify(input)
  eq(r.mode, "none")
end)

test("classify: single line → none", function()
  local input = "  │ just one line"
  local r = clean.classify(input)
  eq(r.mode, "none")
end)

-- ═══════════════════════════════════════════════════════════════
-- Bug fix: sentence ending at wrap point (posture corrector)
-- ═══════════════════════════════════════════════════════════════

test("classify: sentence ending at wrap point counts as wrapped pair", function()
  local input = margin({
    "My coworker spent $200 a month on a chiropractor for her back. I showed her this $3",
    "posture corrector and she hasn't been back since. 10,000 people already figured this out.",
    " Breathable, adjustable, invisible under a shirt. $45 profit per sale at 94% margin.",
    "Would you sell this or wear it? Link in bio for more winning products.",
  })
  local r = clean.classify(input)
  eq(r.mode, "full", "should be full, not " .. r.mode)
end)

test("clean: sentence ending at wrap point rejoins fully", function()
  local input = margin({
    "My coworker spent $200 a month on a chiropractor for her back. I showed her this $3",
    "posture corrector and she hasn't been back since. 10,000 people already figured this out.",
    " Breathable, adjustable, invisible under a shirt. $45 profit per sale at 94% margin.",
    "Would you sell this or wear it? Link in bio for more winning products.",
  })
  local result = clean.clean(input)
  eq(result:find("\n"), nil, "should be one paragraph with no line breaks")
  assert(result:find("this %$3 posture"), "should join '$3' and 'posture' with space")
  assert(result:find("out%. Breathable"), "should join 'out.' and 'Breathable' with space")
end)

-- ═══════════════════════════════════════════════════════════════
-- Bug fix: partial copy first line (protein shaker)
-- ═══════════════════════════════════════════════════════════════

test("classify: partial copy (first line no margin) → full", function()
  -- Selection started mid-line after "Description: "
  local input = "I used to stand there shaking my protein bottle like an idiot after every\n"
    .. "  workout. Then I found this cup with a 7,000 RPM motor hidden inside. Press one button and\n"
    .. "  it blends everything smooth in seconds. USB rechargeable so it goes in your gym bag. $12\n"
    .. "  to source, sell for $40, nearly $28 profit per sale. The gym crowd can't stop buying\n"
    .. "  these. Would you sell it or use it? Link in bio for more winning products."
  local r = clean.classify(input)
  eq(r.mode, "full", "should be full, not " .. r.mode)
end)

test("clean: partial copy first line joins with rest", function()
  local input = "I used to stand there shaking my protein bottle like an idiot after every\n"
    .. "  workout. Then I found this cup with a 7,000 RPM motor hidden inside. Press one button and\n"
    .. "  it blends everything smooth in seconds. USB rechargeable so it goes in your gym bag. $12\n"
    .. "  to source, sell for $40, nearly $28 profit per sale. The gym crowd can't stop buying\n"
    .. "  these. Would you sell it or use it? Link in bio for more winning products."
  local result = clean.clean(input)
  eq(result:find("\n"), nil, "should be one paragraph")
  assert(result:find("every workout"), "should join 'every' and 'workout' with space")
end)

-- ═══════════════════════════════════════════════════════════════
-- Bug fix: hard break mid-word in spaceless text (comma-separated keywords)
-- ═══════════════════════════════════════════════════════════════

test("classify: spaceless text with hard break tail → full", function()
  local input = margin({
    "shopify,ecommerce,saas,b2b,shopifyapps,shopifythemes,analytics,emailmarketing,reviews,loyalty,crm,leadge",
    "neration",
  })
  local r = clean.classify(input)
  eq(r.mode, "full", "should be full, not " .. r.mode)
end)

test("clean: hard break mid-word joins without space", function()
  local input = margin({
    "shopify,ecommerce,saas,b2b,shopifyapps,shopifythemes,analytics,emailmarketing,reviews,loyalty,crm,leadge",
    "neration",
  })
  local result = clean.clean(input)
  eq(result:find("\n"), nil, "should be one line")
  assert(result:find("leadgeneration"), "should join without space, got: " .. result:sub(-30))
  assert(not result:find("leadge neration"), "should NOT have space in middle of word")
end)

-- ═══════════════════════════════════════════════════════════════
-- Paragraph breaks should be preserved
-- ═══════════════════════════════════════════════════════════════

test("clean: blank line between paragraphs is preserved", function()
  local input = piped({
    "First paragraph that is long enough to look like a real line of prose in the terminal.",
    "",
    "Second paragraph that is also long enough to look like prose in a terminal window here.",
  })
  local result = clean.clean(input)
  assert(result:find("\n\n"), "blank line between paragraphs should be preserved")
end)

-- ═══════════════════════════════════════════════════════════════
-- Structural lines should not be rejoined
-- ═══════════════════════════════════════════════════════════════

test("clean: bullet list not rejoined", function()
  local input = piped({
    "- First item in the list",
    "- Second item in the list",
    "- Third item in the list",
  })
  local result = clean.clean(input)
  local lines = {}
  for l in (result .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  eq(#lines, 3, "bullet list should stay as 3 lines")
end)

test("clean: Key: value lines not rejoined", function()
  local input = piped({
    "Title: Something interesting here",
    "Description: A longer description that has some detail about the topic at hand right now.",
  })
  local result = clean.clean(input)
  assert(result:find("\n"), "Key: value lines should stay separate")
end)

-- ═══════════════════════════════════════════════════════════════
-- Code should not be rejoined
-- ═══════════════════════════════════════════════════════════════

test("clean: code lines not rejoined", function()
  local input = piped({
    "const x = 1;",
    "const y = 2;",
    "const z = x + y;",
  })
  local result = clean.clean(input)
  local lines = {}
  for l in (result .. "\n"):gmatch("(.-)\n") do lines[#lines + 1] = l end
  eq(#lines, 3, "code lines should stay as 3 lines")
end)

-- ═══════════════════════════════════════════════════════════════
-- Strip-only mode
-- ═══════════════════════════════════════════════════════════════

test("stripOnly: removes 2-space margin", function()
  local input = "  │ Hello world\n  │ Second line"
  local result = clean.stripOnly(input)
  assert(not result:find("│"), "pipe should be removed")
  assert(result:find("^Hello world"), "margin should be stripped")
end)

-- ═══════════════════════════════════════════════════════════════
-- Results
-- ═══════════════════════════════════════════════════════════════

io.write(string.format("\n%d passed, %d failed\n", passed, failed))
os.exit(failed > 0 and 1 or 0)
