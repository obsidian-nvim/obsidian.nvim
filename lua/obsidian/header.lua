local BufferDocument = require "obsidian.document"
local log = require "obsidian.log"
local parse_header = require "obsidian.parse.header"
local sections = require "obsidian.section"
local util = require "obsidian.util.rename"

local M = {}

--- ATX and setext headings of the buffer, outside code and comments. The section
--- parser takes the line right above the underline as the label of a setext heading
--- (earlier lines of the paragraph stay text), as do the anchors of every link the
--- plugin resolves, so that line is the text renamed here.
---@param bufnr integer
---@return { row: integer, last_row: integer, text: string, anchor: string, start_col: integer, end_col: integer }[]
M.headings = function(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local out = {}
  for _, section in ipairs(sections.parse(lines, { document = BufferDocument.get(bufnr) })) do
    local hr = section.heading_range
    local rows = hr.end_row - hr.start_row
    if section.header then
      local line = lines[hr.start_row + 1] or ""
      -- ATX: skip the `#` marker; setext: the text is the whole first line.
      local s, e = line:find(section.header, rows == 1 and (section.level or 0) + 1 or 1, true)
      if s then
        out[#out + 1] = {
          row = hr.start_row,
          last_row = hr.end_row - 1,
          text = section.header,
          anchor = section.anchor,
          start_col = s - 1,
          end_col = e,
        }
      end
    end
  end
  return out
end

--- A heading component of a link keeps the style it was written in: raw text,
--- URL-encoded, or slug.
---@param component string
---@param old_text string
---@param new_text string
---@return string
local function restyle(component, old_text, new_text)
  if component == old_text then
    return new_text
  end
  if vim.uri_decode(component) ~= component then
    return require("obsidian.uri").encode(new_text)
  end
  if component == parse_header.normalize_anchor(component):sub(2) then
    return parse_header.to_anchor(new_text):sub(2)
  end
  return new_text
end

---@class obsidian.header.RenameOpts : obsidian.rename.Opts

--- Rewrite a heading's text and every link component that names it. Refused when
--- the heading is not unique in its note, because a link cannot say which one it means.
---@param bufnr integer Buffer of the note; 0 for the current one.
---@param old string Heading text or anchor (`My heading`, `#my-heading`).
---@param new_name string
---@param opts obsidian.header.RenameOpts|obsidian.rename.Callback|?
---@param callback obsidian.rename.Callback|?
M.rename = function(bufnr, old, new_name, opts, callback)
  opts, callback = util.args(opts, callback)
  if not opts then
    return
  end
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  local anchor = parse_header.normalize_anchor(old)

  local new_text = vim.trim(new_name)
  if new_text == "" or new_text:find("\n", 1, true) or vim.startswith(new_text, "#") then
    return util.fail(('Invalid heading "%s"'):format(new_text), callback)
  end

  local all = M.headings(bufnr)
  local same = vim.tbl_filter(function(h)
    return h.anchor == anchor
  end, all)
  local definition = same[1]
  if not definition then
    return util.fail(('Heading "%s" not found in this note'):format(old), callback)
  end
  if #same > 1 then
    return util.fail(('Heading "%s" is not unique in this note'):format(definition.text), callback)
  end
  if new_text == definition.text then
    log.info "Identical name"
    return util.finish(opts, callback, nil)
  end
  local new_anchor = parse_header.to_anchor(new_text)
  for _, other in ipairs(all) do
    if other ~= definition and other.anchor == new_anchor then
      return util.fail(('Heading "%s" already exists in this note'):format(new_text), callback)
    end
  end

  util.collect_refs(bufnr, function(collected)
    ---@type obsidian.rename.FileEdits
    local file_edits = {}
    util.add_edit(
      file_edits,
      util.path_key(vim.api.nvim_buf_get_name(bufnr)),
      definition.row,
      definition.start_col,
      definition.end_col,
      new_text
    )
    for _, item in ipairs(collected) do
      for _, comp in ipairs(util.fragment_components(item.ref)) do
        if
          not vim.startswith(comp.text, "^") and parse_header.normalize_anchor(vim.uri_decode(comp.text)) == anchor
        then
          local replacement = restyle(comp.text, definition.text, new_text)
          util.add_edit(file_edits, item.path, item.row, comp.col, comp.col + #comp.text, replacement)
        end
      end
    end
    util.finish(opts, callback, util.to_workspace_edit(file_edits))
  end)
end

return M
