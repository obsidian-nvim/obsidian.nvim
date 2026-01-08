local lpeg = vim.lpeg
local P, R, S = lpeg.P, lpeg.R, lpeg.S
local C, Cp, Ct = lpeg.C, lpeg.Cp, lpeg.Ct

local M = {}

-- Match exactly one UTF-8 codepoint (valid UTF-8 sequences).
local utf8_char = R "\0\127" -- 1-byte (ASCII)
  + R "\194\223" * R "\128\191" -- 2-byte
  + R "\224\239" * R "\128\191" * R "\128\191" -- 3-byte
  + R "\240\244" * R "\128\191" * R "\128\191" * R "\128\191" -- 4-byte

-- A "keyword-ish" previous char that should block tags like "foo#bar".
-- Conservative: ASCII alnum/_ plus *any* non-ASCII codepoint.
-- (You can relax this if you want tags after emoji etc.)
local non_ascii = utf8_char - R "\0\127"
local keyword_prev = R("az", "AZ", "09") + P "_" + non_ascii

-- Allowed characters inside the tag *body* (after '#').
-- ASCII: alnum _ - / ; plus allow any non-ASCII codepoint as part of tag.
local allowed_ascii = R("az", "AZ", "09") + S "_-/"
local allowed = allowed_ascii + non_ascii

local tag_body = allowed ^ 1

-- Tag core captures:
--   start position at '#', tag body string, end position (byte index after body)
local core = Cp() * P "#" * C(tag_body) * Cp()

-- Two ways a tag can start:
--  1) at start of line
--  2) preceded by a non-keyword UTF-8 char (and not a backslash, to avoid \#tag)
local boundary = (utf8_char - keyword_prev - P "\\") * core
local tag_at_bol = P(function(_, i)
  return i == 1 and i or nil
end) * core
local one_tag = tag_at_bol + boundary

-- Find all occurrences anywhere in the line:
-- (skip 1 UTF-8 char at a time until a match is found; repeat)
local all_tags = Ct(((utf8_char - one_tag) ^ 0 * one_tag) ^ 0)

--- Find Obsidian-style tags in a markdown line (Unicode-safe).
--- UTF-8 indices are 0-based and end-exclusive.
---
--- @param line string
--- @return { tag: string, start_idx: integer, end_idx: integer, start_byte: integer, end_byte: integer }[]
M.parse_tags = function(line)
  if string.find(line, "<!--.*-->") ~= nil then
    return {}
  end
  local util = require "obsidian.util"
  local caps = lpeg.match(all_tags, line) or {}
  local out = {}

  local function is_number(tag)
    return tonumber(tag) ~= nil
  end

  local is_bound = function(start_byte_index)
    local char_ahead = line:sub(start_byte_index - 1, start_byte_index - 1)
    return start_byte_index == 1 or char_ahead == " "
  end

  -- Captures come back as a flat array: startCp, tagBody, endCp, repeated...
  for i = 1, #caps, 3 do
    local start_byte_index = caps[i] -- 1-based byte index of '#'
    local tag = caps[i + 1] -- body (no '#')
    local end_byte_index = caps[i + 2] - 1 -- 1-based byte index after body

    if not is_number(tag) and not util.is_hex_color("#" .. tag) and is_bound(start_byte_index) then
      out[#out + 1] = {
        start_byte_index,
        end_byte_index,
        "Tag", -- TODO: return tag directly
        -- vim.str_utfindex(line, start_byte),
        -- vim.str_utfindex(line, end_byte),
      }
    end
  end

  return out
end

return M
