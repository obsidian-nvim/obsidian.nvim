local obsidian = require "obsidian"
local search = require "obsidian.search"
local util = require "obsidian.util"

---@param refs string[]
---@return string[]
local function urlencode_refs(refs)
  local encoded = {}
  for _, ref in ipairs(refs) do
    vim.list_extend(
      encoded,
      util.tbl_unique {
        ref,
        util.urlencode(ref),
        util.urlencode(ref, { keep_path_sep = true }),
      }
    )
  end
  return util.tbl_unique(encoded)
end

---@param location string
---@return string[]
local function default_refs(location)
  local refs = { location }

  local without_suffix = location:gsub("%.md$", "")
  if without_suffix ~= location then
    refs[#refs + 1] = without_suffix
  end

  local basename = vim.fs.basename(location)
  if basename ~= location then
    refs[#refs + 1] = basename
    local basename_without_suffix = basename:gsub("%.md$", "")
    if basename_without_suffix ~= basename then
      refs[#refs + 1] = basename_without_suffix
    end
  end

  return urlencode_refs(util.tbl_unique(refs))
end

---@param location string
---@param callback fun(refs: string[])
local function resolve_refs(location, callback)
  search.resolve_note_async(location, function(notes)
    vim.print(notes)
    if #notes > 0 then
      callback(notes[1]:get_reference_paths { urlencode = true })
    else
      callback(default_refs(location))
    end
  end, { notes = { max_lines = 0 } })
end

---@param match obsidian.LinkMatch
---@param callback fun(label: string|nil)
local function backlink_count_handler(match, callback)
  local location = util.parse_link(match.link, { link_type = match.type })
  if not location then
    callback(nil)
    return
  end

  local anchor
  local block
  location, block = util.strip_block_links(location)
  location, anchor = util.strip_anchor_links(location)

  if location == "" then
    callback(nil)
    return
  end

  resolve_refs(location, function(refs)
    vim.print(refs)
    if vim.tbl_isempty(refs) then
      callback(nil)
      return
    end

    search.find_backlinks_async(nil, function(backlinks)
      local count = #backlinks
      if count <= 1 then
        callback(nil)
      else
        callback(count .. " refs")
      end
    end, { refs = refs, anchor = anchor, block = block })
  end)
end

---@type table<obsidian.search.RefTypes, fun(match: obsidian.LinkMatch, callback: fun(label: string|nil))>
local handlers = {}

handlers.Wiki = backlink_count_handler
handlers.WikiWithAlias = backlink_count_handler
handlers.Markdown = backlink_count_handler

---@param callback fun(_: any, hints: lsp.InlayHint[]|?)
local function get_hints(callback)
  local note = obsidian.api.current_note(0)
  if not note then
    callback(nil, nil)
    return
  end

  local links = note:links()

  local matches = vim.tbl_filter(function(link_match)
    return handlers[link_match.type] ~= nil
  end, links)

  ---@type lsp.InlayHint[]
  local hints = {}
  local pending = #matches

  local function done()
    table.sort(hints, function(a, b)
      if a.position.line == b.position.line then
        return a.position.character < b.position.character
      end
      return a.position.line < b.position.line
    end)
    callback(nil, hints)
  end

  if pending == 0 then
    done()
    return
  end

  local function finish_one()
    pending = pending - 1
    if pending == 0 then
      done()
    end
  end

  for _, match in ipairs(matches) do
    handlers[match.type](match, function(label)
      if label then
        hints[#hints + 1] = {
          position = { line = match.line - 1, character = match["end"] + 1 },
          label = label,
          paddingLeft = true,
          paddingRight = true,
        }
      end
      finish_one()
    end)
  end
end

---@param callback fun(_: any, hints: lsp.InlayHint[]|?)
return function(_, callback)
  get_hints(callback)
end
