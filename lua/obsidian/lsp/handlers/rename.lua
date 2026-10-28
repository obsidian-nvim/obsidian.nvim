local obsidian = require "obsidian"
local rename = require "obsidian.lsp.handlers._rename"

local search = obsidian.search
local log = obsidian.log
local api = obsidian.api

---@param params lsp.RenameParams
return function(params, handler, _)
  local new_name = params.newName
  local bufnr, position = rename.resolve_params(params)
  local source_path = vim.api.nvim_buf_get_name(bufnr)
  local workspace_dir = api.resolve_workspace_dir(source_path)

  local ok, error = pcall(vim.cmd.wall)

  if not ok then
    return log.err(error and error or "failed writing all buffers before renaming, abort")
  end

  local target = rename.target_at(bufnr, position)
  if not target then
    return handler(nil, nil)
  end

  local function do_rename(note)
    note:rename(new_name, { apply = false }, function(err, edit)
      if err or not edit then
        return handler(nil, {})
      end
      handler(nil, edit)
    end)
  end

  if target.kind == "note" and target.ref then
    search.resolve_note_async(target.ref.target, function(notes)
      -- TODO: pick note
      if vim.tbl_isempty(notes) then
        handler(nil, nil)
        return
      end
      do_rename(notes[1])
    end, { dir = workspace_dir, buf_dir = source_path ~= "" and vim.fs.dirname(source_path) or nil })
  else
    local function done(err, edit)
      handler(nil, not err and edit or nil)
    end
    local opts = { apply = false }
    if target.kind == "block" then
      require("obsidian.block").rename(bufnr, target.id --[[@as string]], new_name, opts, done)
    elseif target.kind == "heading" then
      require("obsidian.header").rename(bufnr, target.anchor --[[@as string]], new_name, opts, done)
    elseif target.kind == "footnote" then
      require("obsidian.footnotes").rename(bufnr, target.id --[[@as string]], new_name, opts, done)
    elseif target.kind == "tag" then
      require("obsidian.tag").rename(target.id --[[@as string]], new_name, { apply = false, dir = workspace_dir }, done)
    elseif target.kind == "attachment" then
      require("obsidian.attachment").rename(
        target.ref and target.ref.target or "",
        new_name,
        { apply = false, filename = source_path },
        done
      )
    end
  end
end
