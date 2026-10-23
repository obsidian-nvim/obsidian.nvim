local api = require "obsidian.api"

local M = {}

---Find other .md files with the same stem in the note's workspace.
---Use the filesystem, not the optional cache, so a newly created note is visible.
---@param path string
---@param workspace obsidian.Workspace
---@return boolean
local function has_stem_conflict(path, workspace)
  local name = vim.fs.basename(path):lower()
  local matches = vim.fs.find(function(entry, dir)
    return entry:lower() == name and api.path_is_note(vim.fs.joinpath(dir, entry), workspace)
  end, { path = tostring(workspace.root), type = "file", limit = 2 })
  for _, candidate in ipairs(matches) do
    if vim.fs.normalize(candidate) ~= vim.fs.normalize(path) then
      return true
    end
  end
  return false
end

---Render a link to a note from a specific source file. This function does not edit a buffer.
---@param note obsidian.Note
---@param opts obsidian.note.FormatLinkOpts & { source_path: string? }
---@return string
function M.render(note, opts)
  opts = opts or {}
  local path = tostring(assert(note.path, "note path is required"))
  local source_path = opts.source_path
  local workspace = api.find_workspace(source_path or path)
  local format = opts.format or Obsidian.opts.link.format
  local conflict = workspace and vim.endswith(path, ".md") and has_stem_conflict(path, workspace) or false

  if conflict and format == "shortest" then
    if opts.format then
      error("shortest link cannot identify note with a duplicate filename: " .. path)
    end
    format = "absolute"
  elseif conflict and format == "relative" and workspace and vim.fs.dirname(path) == tostring(workspace.root) then
    format = "absolute"
  end

  local link_opts = vim.tbl_extend("force", {}, opts, {
    dir = opts.dir or (source_path and vim.fs.dirname(source_path) or nil),
    format = format,
  })
  link_opts.source_path = nil
  return note:format_link(link_opts)
end

return M
