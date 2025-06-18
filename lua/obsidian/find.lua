local search = require "obsidian.search"

local function strip_tag(s)
  if vim.startswith(s, "#") then
    return string.sub(s, 2)
  elseif vim.startswith(s, "  - ") then
    return string.sub(s, 5)
  end
  return s
end

---@class obsidian._TagLocation
---
---@field tag string The tag found.
---@field path string|obsidian.Path The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field tag_start integer|? The index within 'text' where the tag starts.
---@field tag_end integer|? The index within 'text' where the tag ends.

-- TODO: query properly ignore_case, music and Music is same tag

---@param query string | table
---@param on_match fun(tag_loc: obsidian._TagLocation)
---@param on_finish fun(tag_locs: obsidian._TagLocation[])
---@param opts? { dir: string }
---@async
local function find_tag(query, on_match, on_finish, opts)
  vim.validate("query", query, { "string", "table" })
  vim.validate("on_match", on_match, "function")
  vim.validate("on_finish", on_finish, "function")
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, { dir = tostring(require("obsidian").get_client().dir) })

  local terms = type(query) == "string" and { query } or query ---@cast terms -string

  local search_terms = {}
  for _, term in ipairs(terms) do
    search_terms[#search_terms + 1] = "\\B#([\\p{L}\\p{N}_-]*" .. term .. "[\\p{L}\\p{N}_-]*)" -- tags in the wild
  end

  local results = {}

  search.search_async(opts.dir, search_terms, { ignore_case = true }, function(match)
    local tag_match = match.submatches[1]

    ---@type obsidian._TagLocation
    local tag_loc = {
      tag_start = tag_match.start,
      tag_end = tag_match["end"],
      tag = strip_tag(tag_match.match.text),
      path = match.path.text,
      line = match.line_number,
    }
    table.insert(results, tag_loc)
    on_match(tag_loc)
  end, function(exit_code)
    assert(exit_code == 0)
    on_finish(results)
  end)
end

local function list_tags(callback)
  vim.validate("callback", callback, "function")
  local found = {}
  find_tag("", function(tag_loc)
    found[tag_loc.tag] = true
  end, function(tag_locs)
    callback(vim.tbl_keys(found))
  end)
end

--  BUG: markdown list item ... just use cache value...

list_tags(vim.print)

return {
  find_tag = find_tag,
}
