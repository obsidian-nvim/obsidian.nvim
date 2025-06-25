local search = require "obsidian.search"
local util = require "obsidian.util"

local function strip_tag(s)
  if vim.startswith(s, "#") then
    return string.sub(s, 2)
  end
  return s
end

---@class obsidian.TagLocation
---
---@field tag string The tag found.
---@field path string The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field tag_start integer|? The index within 'text' where the tag starts.
---@field tag_end integer|? The index within 'text' where the tag ends.

-- TODO: properly ignore_case, music and Music is same tag

---@param query string | table
---@param opts { dir: string, on_match: fun(tag_loc: obsidian.TagLocation) }
---@param on_finish fun(exit_code: integer, tag_locs: obsidian.TagLocation[])
---@async
local function find(query, opts, on_finish)
  vim.validate("query", query, { "string", "table" })
  vim.validate("on_finish", on_finish, "function")
  opts = opts or {}
  opts.dir = opts.dir or require("obsidian").get_client().dir

  local terms = type(query) == "string" and { query } or query ---@cast terms -string

  local search_terms = {}
  for _, term in ipairs(terms) do
    if term ~= "" then
      -- Match tags that contain the term
      search_terms[#search_terms + 1] = "\\B#([\\p{L}\\p{N}_-]*" .. term .. "[\\p{L}\\p{N}_-]*)" -- tags in the wild
    else
      -- Match any valid non-empty tag
      search_terms[#search_terms + 1] = "\\B#([\\p{L}\\p{N}_-]+)"
    end
  end

  local results = {}

  search.search_async(opts.dir, search_terms, { ignore_case = true }, function(match)
    local tag_match = match.submatches[1]
    local match_text = tag_match.match.text
    if util.is_hex_color(match_text) then
      return
    end
    ---@type obsidian.TagLocation
    local tag_loc = {
      tag_start = tag_match.start,
      tag_end = tag_match["end"],
      tag = strip_tag(match_text),
      path = match.path.text,
      line = match.line_number,
    }
    table.insert(results, tag_loc)
    if opts.on_match then
      opts.on_match(tag_loc)
    end
  end, function(exit_code)
    on_finish(exit_code, results)
  end)
end

local function list(callback)
  vim.validate("callback", callback, "function")
  local found = {}
  find("", {
    on_match = function(tag_loc)
      found[tag_loc.tag] = true
    end,
  }, function()
    callback(vim.tbl_keys(found))
  end)
end

return {
  find = find,
  list = list,
}
