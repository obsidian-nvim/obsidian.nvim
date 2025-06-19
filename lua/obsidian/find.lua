local search = require "obsidian.search"
local util = require "obsidian.util"
local Note = require "obsidian.note"
local Path = require "obsidian.path"

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

---@class obsidian._BacklinkMatches
---
---@field note obsidian.Note The note instance where the backlinks were found.
---@field path string|obsidian.Path The path to the note where the backlinks were found.
---@field matches obsidian.BacklinkMatch[] The backlinks within the note.

---@class obsidian._BacklinkMatch
---
---@field line integer The line number (1-indexed) where the backlink was found.
---@field text string The text of the line where the backlink was found.

local n = Note.from_file "~/Notes/21-30 Tinker/13 Music/13.1 kpop/dem jointz.md"

local function build_backlink_search_term(note, anchor, block)
  -- Prepare search terms.
  local search_terms = {}
  local note_path = Path.new(note.path)
  for raw_ref in
    vim.iter {
      tostring(note.id),
      note_path.name,
      note_path.stem,
      -- self:vault_relative_path(note.path), -- TODO:
    }
  do
    for ref in
      vim.iter(util.tbl_unique {
        raw_ref,
        util.urlencode(tostring(raw_ref)),
        util.urlencode(tostring(raw_ref), { keep_path_sep = true }),
      })
    do
      if ref ~= nil then
        if anchor == nil and block == nil then
          -- Wiki links without anchor/block.
          search_terms[#search_terms + 1] = string.format("[[%s]]", ref)
          search_terms[#search_terms + 1] = string.format("[[%s|", ref)
          -- Markdown link without anchor/block.
          search_terms[#search_terms + 1] = string.format("(%s)", ref)
          -- Markdown link without anchor/block and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s)", ref)
          -- Wiki links with anchor/block.
          search_terms[#search_terms + 1] = string.format("[[%s#", ref)
          -- Markdown link with anchor/block.
          search_terms[#search_terms + 1] = string.format("(%s#", ref)
          -- Markdown link with anchor/block and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s#", ref)
        elseif anchor then
          -- Note: Obsidian allow a lot of different forms of anchor links, so we can't assume
          -- it's the standardized form here.
          -- Wiki links with anchor.
          search_terms[#search_terms + 1] = string.format("[[%s#", ref)
          -- Markdown link with anchor.
          search_terms[#search_terms + 1] = string.format("(%s#", ref)
          -- Markdown link with anchor and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s#", ref)
        elseif block then
          -- Wiki links with block.
          search_terms[#search_terms + 1] = string.format("[[%s#%s", ref, block)
          -- Markdown link with block.
          search_terms[#search_terms + 1] = string.format("(%s#%s", ref, block)
          -- Markdown link with block and is relative to root.
          search_terms[#search_terms + 1] = string.format("(/%s#%s", ref, block)
        end
      end
    end
  end
  for alias in vim.iter(note.aliases) do
    if anchor == nil and block == nil then
      -- Wiki link without anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s]]", alias)
      -- Wiki link with anchor/block.
      search_terms[#search_terms + 1] = string.format("[[%s#", alias)
    elseif anchor then
      -- Wiki link with anchor.
      search_terms[#search_terms + 1] = string.format("[[%s#", alias)
    elseif block then
      -- Wiki link with block.
      search_terms[#search_terms + 1] = string.format("[[%s#%s", alias, block)
    end
  end

  return search_terms
end

local function find_backlinks(note, on_match, on_finish, opts)
  local client = require("obsidian").get_client()

  vim.validate("query", note, { "table" }) -- TODO:
  vim.validate("on_match", on_match, "function")
  vim.validate("on_finish", on_finish, "function")
  opts = opts or {}
  opts = vim.tbl_extend("keep", opts, { dir = tostring(require("obsidian").get_client().dir) })

  local block = opts.block and util.standardize_block(opts.block) or nil
  local anchor = opts.anchor and util.standardize_anchor(opts.anchor) or nil

  local on_line = function(match) end

  search.search_async(
    opts.dir,
    build_backlink_search_term(note, anchor, block),
    client:_prepare_search_opts(opts.search, { fixed_strings = true, ignore_case = true }),
    on_line,
    function(code)
      assert(code == 0)
      ---@type obsidian.BacklinkMatches[]
      local results = {}

      -- Order by path.
      local paths = {}
      for path, idx in pairs(path_order) do
        paths[idx] = path
      end

      -- Gather results.
      for i, path in ipairs(paths) do
        results[i] = { note = path_to_note[path], path = path, matches = backlink_matches[path] }
      end

      -- Log any errors.
      if first_err ~= nil and first_err_path ~= nil then
        log.err(
          "%d error(s) occurred during search. First error from note at '%s':\n%s",
          err_count,
          first_err_path,
          first_err
        )
      end

      callback(vim.tbl_filter(function(bl)
        return bl.matches ~= nil
      end, results))
    end
  )
end

local t = {
  "[[dem jointz]]",
  "[[dem jointz|",
  "(dem jointz)",
  "(/dem jointz)",
  "[[dem jointz#",
  "(dem jointz#",
  "(/dem jointz#",
  "[[dem%20jointz]]",
  "[[dem%20jointz|",
  "(dem%20jointz)",
  "(/dem%20jointz)",
  "[[dem%20jointz#",
  "(dem%20jointz#",
  "(/dem%20jointz#",
  "[[dem jointz.md]]",
  "[[dem jointz.md|",
  "(dem jointz.md)",
  "(/dem jointz.md)",
  "[[dem jointz.md#",
  "(dem jointz.md#",
  "(/dem jointz.md#",
  "[[dem%20jointz.md]]",
  "[[dem%20jointz.md|",
  "(dem%20jointz.md)",
  "(/dem%20jointz.md)",
  "[[dem%20jointz.md#",
  "(dem%20jointz.md#",
  "(/dem%20jointz.md#",
  "[[dem jointz]]",
  "[[dem jointz|",
  "(dem jointz)",
  "(/dem jointz)",
  "[[dem jointz#",
  "(dem jointz#",
  "(/dem jointz#",
  "[[dem%20jointz]]",
  "[[dem%20jointz|",
  "(dem%20jointz)",
  "(/dem%20jointz)",
  "[[dem%20jointz#",
  "(dem%20jointz#",
  "(/dem%20jointz#",
}

return {
  find_tag = find_tag,
}
