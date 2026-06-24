local obsidian = require "obsidian"

local search = obsidian.search
local log = obsidian.log
local api = obsidian.api
local util = obsidian.util

---@param params lsp.RenameParams
return function(params, handler, _)
  local new_name = params.newName

  local ok, err = pcall(vim.cmd.wall)

  if not ok then
    return log.err(err and err or "failed writing all buffers before renaming, abort")
  end

  local cur_link = api.cursor_link()

  local function do_rename(note)
    note:rename(new_name, { apply = false }, function(err, edit)
      if err or not edit then
        return handler(nil, {})
      end
      handler(nil, edit)
    end)
  end

  if cur_link then
    local loc = util.parse_link(cur_link)
    assert(loc, "wrong link format")
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
