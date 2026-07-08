local search = require "obsidian.search"
local log = require "obsidian.log"
local api = require "obsidian.api"
local util = require "obsidian.util"
local attachment_rename = require "obsidian.lsp.handlers._rename_attachment"

local M = require "obsidian.lsp.handlers._rename"

---@param params lsp.RenameParams
return function(params, handler, _)
  local new_name = params.newName

  local ok, err = pcall(vim.cmd.wall)

  if not ok then
    return log.err(err and err or "failed writing all buffers before renaming, abort")
  end

  local cur_link = api.cursor_link()

  local function do_rename(note)
    local old_stem = note.path and note.path.stem or nil
    if new_name == note.id or (old_stem and new_name == old_stem) then
      log.info "Identical name"
      return handler(nil, {})
    end
    if not M.validate(new_name) then
      log.info "Note with same name exists"
      return handler(nil, {})
    end
    M.rename(note, new_name, handler)
  end

  if cur_link then
    local loc = util.parse_link(cur_link)
    assert(loc, "wrong link format")

    local attachment_path = attachment_rename.resolve_link(loc)
    if attachment_path then
      return attachment_rename.rename(attachment_path, new_name, handler)
    end

    local stripped = util.strip_anchor_links(loc)
    stripped = util.strip_block_links(stripped)
    loc = stripped ~= "" and stripped or loc

    search.resolve_note_async(loc, function(notes)
      -- TODO: pick note
      if vim.tbl_isempty(notes) then
        return
      end
      do_rename(notes[1])
    end)
  else
    do_rename(assert(api.current_note(0)))
  end
end
