local BufferDocument = require "obsidian.document"
local Document = require "obsidian.parse.document"
local parse_block_id = require "obsidian.parse.block_id"
local Range = require "obsidian.range"
local log = require "obsidian.log"
local rstrip = require("obsidian.util").rstrip_whitespace

local M = {}

---@class obsidian.block.CreateReferenceOpts
---@field target_path string
---@field target_bufnr integer?
---@field target_range obsidian.Range Whole lines of the target block; ends at the start of the next row.
---@field target_checksum string Checksum of the target buffer with trailing whitespace removed.
---@field block_id string Block ID with its leading `^`.
---@field placement "inline"|"list-item"|"standalone"
---@field indent string?
---@field source_bufnr integer
---@field source_range obsidian.Range Range of the source placeholder.
---@field source_text string Link replacing the placeholder.
---@field placeholder string Expected current text of the source range.

--- Block IDs defined in the document, outside code and comments.
---@param document obsidian.parse.Document
---@return { id: string, row: integer, start_col: integer, end_col: integer }[]
local function block_definitions(document)
  local out = {}
  for row, line in ipairs(document.lines) do
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

---@param lines string[]
---@param block_id string
---@return boolean
local function contains_block_id(lines, block_id)
  for _, definition in ipairs(block_definitions(Document.parse(lines))) do
    if "^" .. definition.id == block_id then
      return true
    end
  end
  return false
end

---@param edits lsp.TextEdit[]
---@param bufnr integer
---@return boolean
local function apply_text_edits(edits, bufnr)
  local ok, err = pcall(vim.lsp.util.apply_text_edits, edits, bufnr, "utf-8")
  if not ok then
    log.err("Failed to apply block reference edit: %s", err)
    return false
  end
  return true
end

--- Label a block and replace the source placeholder with a link to it. Both
--- snapshots must still match. Leave loaded buffers unsaved, but persist the ID
--- before linking if the target had to be loaded from disk.
---@param opts obsidian.block.CreateReferenceOpts
function M.create_reference(opts)
  if not vim.api.nvim_buf_is_valid(opts.source_bufnr) then
    return
  end

  local source_range = opts.source_range
  local source = vim.api.nvim_buf_get_text(
    opts.source_bufnr,
    source_range.start_row,
    source_range.start_col,
    source_range.end_row,
    source_range.end_col,
    {}
  )
  if #source ~= 1 or source[1] ~= opts.placeholder then
    return log.warn "Block reference completion is no longer current"
  end

  local target_bufnr = opts.target_bufnr
  if not target_bufnr or not vim.api.nvim_buf_is_valid(target_bufnr) then
    target_bufnr = vim.fn.bufnr(opts.target_path)
  end
  local target_was_loaded = target_bufnr > 0 and vim.api.nvim_buf_is_loaded(target_bufnr)
  if target_bufnr < 1 then
    target_bufnr = vim.fn.bufadd(opts.target_path)
  end
  vim.fn.bufload(target_bufnr)
  if not vim.bo[target_bufnr].modifiable or vim.bo[target_bufnr].readonly then
    return log.warn "Target block is not writable"
  end

  local target_lines = vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false)
  local normalized_target = vim.tbl_map(rstrip, target_lines)
  if vim.fn.sha256(table.concat(normalized_target, "\n")) ~= opts.target_checksum then
    return log.warn "Block changed before its reference could be created"
  end
  if contains_block_id(target_lines, opts.block_id) then
    return log.warn "Generated block ID already exists"
  end

  local target_range = opts.target_range
  local target = vim.api.nvim_buf_get_lines(target_bufnr, target_range.start_row, target_range.end_row, false)
  if #target == 0 then
    return log.warn "Target block no longer exists"
  end

  local target_row = target_range.end_row - 1
  local target_col = #target[#target]
  local next_line = target_lines[target_range.end_row + 1]
  local has_blank_after = next_line ~= nil and vim.trim(next_line) == ""
  local target_text = " " .. opts.block_id
  if opts.placement == "standalone" then
    target_text = "\n\n" .. opts.block_id .. (has_blank_after and "" or "\n")
  elseif opts.placement == "list-item" then
    target_text = "\n" .. (opts.indent or "    ") .. opts.block_id
  end
  local target_edit = {
    range = Range.to_lsp(Range.new(target_row, target_col, target_row, target_col), "utf-8"),
    newText = target_text,
  }
  local source_edit = { range = Range.to_lsp(source_range, "utf-8"), newText = opts.source_text }

  if target_bufnr == opts.source_bufnr then
    if not apply_text_edits({ target_edit, source_edit }, target_bufnr) then
      return
    end
  else
    if not apply_text_edits({ target_edit }, target_bufnr) then
      return
    end
    if not target_was_loaded then
      local ok, err = pcall(vim.api.nvim_buf_call, target_bufnr, function()
        vim.cmd "silent write"
      end)
      if not ok then
        log.err("Failed to save block ID in '%s': %s", opts.target_path, err)
        return
      end
    end
    if not contains_block_id(vim.api.nvim_buf_get_lines(target_bufnr, 0, -1, false), opts.block_id) then
      log.err("Block ID was removed while saving '%s'", opts.target_path)
      return
    end
    if not apply_text_edits({ source_edit }, opts.source_bufnr) then
      return
    end
  end

  if vim.api.nvim_get_current_buf() == opts.source_bufnr then
    local row = source_range.start_row
    if target_bufnr == opts.source_bufnr and target_row < row then
      row = row + select(2, target_text:gsub("\n", ""))
    end
    vim.api.nvim_win_set_cursor(0, { row + 1, source_range.start_col + #opts.source_text })
  end
  require("obsidian.ui").update(opts.source_bufnr)
end

---@class obsidian.block.RenameOpts : obsidian.rename.Opts

--- Rewrite a block id in its definition and in every reference to it.
---@param bufnr integer Buffer of the note defining the block; 0 for the current one.
---@param old_id string Block id, with or without the leading `^`.
---@param new_id string
---@param opts obsidian.block.RenameOpts|obsidian.rename.Callback|?
---@param callback obsidian.rename.Callback|?
M.rename = function(bufnr, old_id, new_id, opts, callback)
  local util = require "obsidian.util.rename"
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
  for _, def in ipairs(block_definitions(BufferDocument.get(bufnr))) do
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
