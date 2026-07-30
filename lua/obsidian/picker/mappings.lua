local M = {}

local Note = require "obsidian.note"
local log = require "obsidian.log"
local api = require "obsidian.api"

---@param path string
M.insert_link = function(path)
  if not path or path == "" then
    return
  end
  local link
  if not vim.uv.fs_stat(path) then
    link = api.format_link { path = path }
  else
    local note = Note.from_file(path)
    link = note:format_link()
  end
  vim.api.nvim_put({ link }, "", false, true)
  require("obsidian.ui").update(0)
end

---@param ... string
M.tag_note = function(...)
  local calling_bufnr = require("obsidian.picker").state.calling_bufnr
  local tags = { ... }

  local note = api.current_note(calling_bufnr)
  if not note then
    log.warn("'%s' is not a note in your workspace", vim.api.nvim_buf_get_name(calling_bufnr))
    return
  end

  -- Add the tag and save the new frontmatter to the buffer.
  local tags_added = {}
  local tags_not_added = {}
  for _, tag in ipairs(tags) do
    if note:add_tag(tag) then
      table.insert(tags_added, tag)
    else
      table.insert(tags_not_added, tag)
    end
  end

  if #tags_added > 0 then
    if note:update_frontmatter(calling_bufnr) then
      log.info("Added tags %s to frontmatter", tags_added)
    else
      log.warn "Frontmatter unchanged"
    end
  end

  if #tags_not_added > 0 then
    log.warn("Note already has tags %s", tags_not_added)
  end
end

---@param tag string
M.insert_tag = function(tag)
  if tag == nil then
    log.err "Tag does not exist"
    return
  end
  vim.api.nvim_put({ "#" .. tag }, "", false, true)
end

M.new_note = function(query)
  if not query or vim.trim(query) == "" then
    return
  end
  ---@diagnostic disable-next-line: missing-fields,param-type-mismatch
  require "obsidian.commands.new" { args = query }
end

return M
