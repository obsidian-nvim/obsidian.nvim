local Note = require "obsidian.note"
local search = require "obsidian.search"
local util = require "obsidian.util"

--- Cache: path → { anchor → count }
---@type table<string, table<string, integer>>
local cache = {}

--- Collect all backlinks to a note, group by standardized anchor → count.
--- Backlinks without an anchor are skipped (footer handles note-level count).
---@param note obsidian.Note
---@param callback fun(counts: table<string, integer>)
local function count_header_backlinks_async(note, callback)
  search.find_backlinks_async(note, function(backlinks)
    ---@type table<string, integer>
    local counts = {}
    for _, bl in ipairs(backlinks) do
      if bl.text and bl.start and bl["end"] and bl.start > 0 then
        local ref_text = bl.text:sub(bl.start, bl["end"])
        local link_location = util.parse_link(ref_text)
        if link_location then
          local _, matched_anchor = util.strip_anchor_links(link_location)
          if matched_anchor then
            counts[matched_anchor] = (counts[matched_anchor] or 0) + 1
          end
        end
      end
    end
    cache[tostring(note.path)] = counts
    callback(counts)
  end, {})
end

---@param headers { anchor: string, line: integer }[]
---@param counts table<string, integer>
---@param note_uri string
---@return lsp.CodeLens[]
local function make_lenses(headers, counts, note_uri)
  ---@type lsp.CodeLens[]
  local lenses = {}
  for _, h in ipairs(headers) do
    local n = counts[h.anchor] or 0
    if n > 0 then
      local title = n == 1 and "1 reference" or (n .. " references")
      lenses[#lenses + 1] = {
        range = {
          start = { line = h.line, character = 0 },
          ["end"] = { line = h.line, character = 0 },
        },
        command = {
          title = title,
          command = "obsidian.show_references",
          arguments = { note_uri, h.line },
        },
        data = {},
      }
    end
  end
  return lenses
end

---@param params lsp.CodeLensParams
---@param callback fun(err: any, result: lsp.CodeLens[]?)
return function(params, callback)
  local uri = params.textDocument.uri
  local buf = vim.uri_to_bufnr(uri)

  if not vim.api.nvim_buf_is_valid(buf) then
    return callback(nil, {})
  end

  local note = Note.from_buffer(buf, { collect_anchor_links = true })
  if not note then
    return callback(nil, {})
  end

  -- Collect headers from buffer
  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  ---@type { anchor: string, line: integer }[]
  local headers = {}
  for i, line in ipairs(lines) do
    local h = util.parse_header(line)
    if h then
      headers[#headers + 1] = {
        anchor = util.header_to_anchor(h.header),
        line = i - 1, -- 0-indexed
      }
    end
  end

  if #headers == 0 then
    return callback(nil, {})
  end

  local note_uri = vim.uri_from_fname(tostring(note.path))
  local path_key = tostring(note.path)

  -- Return cached result, refresh async for next request
  local cached = cache[path_key]
  if cached then
    callback(nil, make_lenses(headers, cached, note_uri))
    -- Refresh cache in background for next time
    count_header_backlinks_async(note, function() end)
  else
    -- First time: must wait for result
    count_header_backlinks_async(note, function(counts)
      vim.schedule(function()
        callback(nil, make_lenses(headers, counts, note_uri))
      end)
    end)
  end
end
