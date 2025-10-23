local obsidian = require "obsidian"

local search = obsidian.search
local log = obsidian.log
local api = obsidian.api
local util = obsidian.util

local M = require "obsidian.lsp.handlers._rename"

---@param params lsp.RenameParams
return function(params, handler, _)
  local new_name = params.newName

  local ok, err = pcall(vim.cmd.wall)

  if not ok then
    return log.err(err and err or "failed writing all buffers before renaming, abort")
  end

  -- TODO: check if old == new then return {}
  if not M.validate(new_name) then
    return handler(nil, {}) -- TODO:
    -- return log.warn "Invalid rename id, note with the same id/filename already exists"
  end

  local cur_link = api.cursor_link()

  if cur_link then
    local loc = util.parse_link(cur_link, { strip = true })
    assert(loc, "wrong link format")
    local notes = search.resolve_note(loc)
    -- TODO: pick note
    if vim.tbl_isempty(notes) then
      return
    end
    local note = notes[1]
    M.rename(note, new_name, handler)
  else
    local note = assert(api.current_note(0))
    M.rename(note, new_name, handler)
  end
end
