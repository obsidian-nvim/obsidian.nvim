local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local parse_block_id = require "obsidian.parse.block_id"
local util = require "obsidian.util.rename"

local M = {}

--- Block ids defined in the buffer, outside code and comments.
---@param bufnr integer
---@return { id: string, row: integer, start_col: integer, end_col: integer }[]
local function block_definitions(bufnr)
  local document = BufferDocument.get(bufnr)
  local out = {}
  for row, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
    for _, block in ipairs(parse_block_id.extract(line, { row = row - 1, lexical = true })) do
      if not document:intersects(block.range, Document.BODY_EXCLUSIONS) then
        out[#out + 1] = {
          id = block.raw:sub(2),
          row = row - 1,
          start_col = block.range.start_col + 1,
          end_col = block.range.end_col,
        }
      end
    end
  end
  return out
end

---@class obsidian.block.RenameOpts : obsidian.rename.Opts

--- Rewrite a block id in its definition and in every reference to it.
---@param bufnr integer Buffer of the note defining the block; 0 for the current one.
---@param old_id string Block id, with or without the leading `^`.
---@param new_id string
---@param opts obsidian.block.RenameOpts|obsidian.rename.Callback|?
---@param callback obsidian.rename.Callback|?
M.rename = function(bufnr, old_id, new_id, opts, callback)
  opts, callback = util.args(opts, callback)
  if not opts then
    return
  end
  if bufnr == 0 then
    bufnr = vim.api.nvim_get_current_buf()
  end
  old_id = old_id:gsub("^%^", "")
  new_id = vim.trim(new_id):gsub("^%^", "")

  if not new_id:match "^%w[%w-]*$" then
    return util.fail(('Invalid block id "%s": use letters, digits and "-"'):format(new_id), callback)
  end
  if new_id == old_id then
    require("obsidian.log").info "Identical name"
    return util.finish(opts, callback, nil)
  end

  local definition
  for _, def in ipairs(block_definitions(bufnr)) do
    if def.id == old_id then
      definition = def
    elseif def.id == new_id then
      return util.fail(('Block id "^%s" already exists in this note'):format(new_id), callback)
    end
  end
  if not definition then
    return util.fail(('Block "^%s" not found in this note'):format(old_id), callback)
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
      new_id
    )
    for _, item in ipairs(collected) do
      if item.ref.block == old_id then
        for _, comp in ipairs(util.fragment_components(item.ref)) do
          if comp.text == "^" .. old_id then
            util.add_edit(file_edits, item.path, item.row, comp.col + 1, comp.col + #comp.text, new_id)
          end
        end
      end
    end
    util.finish(opts, callback, util.to_workspace_edit(file_edits))
  end)
end

return M
