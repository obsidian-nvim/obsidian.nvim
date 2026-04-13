local Note = require "obsidian.note"
local search = require "obsidian.search"
local util = require "obsidian.util"

--- Cache: path → { note_count, anchors: { anchor → count } }
---@type table<string, { note_count: integer, anchors: table<string, integer> }>
local cache = {}

--- Collect all backlinks to a note, split into note-level vs anchor-level counts.
---@param note obsidian.Note
---@param callback fun(result: { note_count: integer, anchors: table<string, integer> })
local function count_backlinks_async(note, callback)
  search.find_backlinks_async(note, function(backlinks)
    local note_count = 0
    ---@type table<string, integer>
    local anchors = {}
    for _, bl in ipairs(backlinks) do
      if bl.text and bl.start and bl["end"] and bl.start > 0 then
        local ref_text = bl.text:sub(bl.start, bl["end"])
        local link_location = util.parse_link(ref_text)
        if link_location then
          local _, matched_anchor = util.strip_anchor_links(link_location)
          if matched_anchor then
            anchors[matched_anchor] = (anchors[matched_anchor] or 0) + 1
          else
            note_count = note_count + 1
          end
        end
      else
        note_count = note_count + 1
      end
    end
    local result = { note_count = note_count, anchors = anchors }
    cache[tostring(note.path)] = result
    callback(result)
  end, {})
end

---@param n integer
---@return string
local function ref_title(n)
  return n == 1 and "1 reference" or (n .. " references")
end

---@param headers { anchor: string, line: integer }[]
---@param result { note_count: integer, anchors: table<string, integer> }
---@param note_uri string
---@return lsp.CodeLens[]
local function make_lenses(headers, result, note_uri)
  ---@type lsp.CodeLens[]
  local lenses = {}

  -- Note-level lens at line 0
  if result.note_count > 0 then
    lenses[#lenses + 1] = {
      range = {
        start = { line = 0, character = 0 },
        ["end"] = { line = 0, character = 0 },
      },
      command = {
        title = ref_title(result.note_count) .. " to note",
        command = "obsidian.show_references",
        arguments = { note_uri, -1 },
      },
      data = {},
    }
  end

  -- Per-header lenses
  for _, h in ipairs(headers) do
    local n = result.anchors[h.anchor] or 0
    if n > 0 then
      lenses[#lenses + 1] = {
        range = {
          start = { line = h.line, character = 0 },
          ["end"] = { line = h.line, character = 0 },
        },
        command = {
          title = ref_title(n),
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

  local note_uri = vim.uri_from_fname(tostring(note.path))
  local path_key = tostring(note.path)

  -- Return cached result, refresh async for next request
  local cached = cache[path_key]
  if cached then
    callback(nil, make_lenses(headers, cached, note_uri))
    count_backlinks_async(note, function() end)
  else
    count_backlinks_async(note, function(result)
      vim.schedule(function()
        callback(nil, make_lenses(headers, result, note_uri))
      end)
    end)
  end
end
