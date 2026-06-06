local Note = require "obsidian.note"
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
    if #notes > 0 then
      callback(notes[1]:get_reference_paths { urlencode = true })
    else
      callback(default_refs(location))
    end
  end, { notes = { max_lines = 0 } })
end

---@param n integer
---@return string
local function ref_title(n)
  return n == 1 and "1 ref" or (n .. " refs")
end

---@param match obsidian.LinkMatch
---@param callback fun(lens: lsp.CodeLens|nil)
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
    if vim.tbl_isempty(refs) then
      callback(nil)
      return
    end

    search.find_backlinks_async(nil, function(backlinks)
      local count = #backlinks
      if count <= 1 then
        callback(nil)
      else
        callback {
          range = {
            start = { line = match.line - 1, character = match.start },
            ["end"] = { line = match.line - 1, character = match["end"] + 1 },
          },
          command = {
            title = ref_title(count),
            command = "obsidian.show_references",
            arguments = { match.link },
          },
          data = {},
        }
      end
    end, { refs = refs, anchor = anchor, block = block })
  end)
end

---@type table<obsidian.search.RefTypes, fun(match: obsidian.LinkMatch, callback: fun(lens: lsp.CodeLens|nil))>
local handlers = {}

handlers.Wiki = backlink_count_handler
handlers.WikiWithAlias = backlink_count_handler
handlers.Markdown = backlink_count_handler

---@param note obsidian.Note
---@param callback fun(err: any, lenses: lsp.CodeLens[]?)
local function get_lenses(note, callback)
  local links = note:links()

  local matches = vim.tbl_filter(function(link_match)
    return handlers[link_match.type] ~= nil
  end, links)

  ---@type lsp.CodeLens[]
  local lenses = {}
  local pending = #matches

  local function done()
    table.sort(lenses, function(a, b)
      if a.range.start.line == b.range.start.line then
        return a.range.start.character < b.range.start.character
      end
      return a.range.start.line < b.range.start.line
    end)
    callback(nil, lenses)
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
    local ok, err = pcall(handlers[match.type], match, function(lens)
      if lens then
        lenses[#lenses + 1] = lens
      end
      finish_one()
    end)

    if not ok then
      vim.schedule(function()
        error(err)
      end)
      finish_one()
    end
  end
end

---@param params lsp.CodeLensParams
---@param callback fun(err: any, result: lsp.CodeLens[]?)
return function(params, callback)
  local uri = params.textDocument.uri
  local buf = vim.uri_to_bufnr(uri)

  if not vim.api.nvim_buf_is_valid(buf) then
    callback(nil, {})
    return
  end

  local note = Note.from_buffer(buf)
  if not note then
    callback(nil, {})
    return
  end

  get_lenses(note, callback)
end
