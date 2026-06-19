local util = require "obsidian.util"

local M = {}

---@param path string
---@return string
local function basename(path)
  return vim.fn.fnamemodify(path, ":t:r")
end

---@param path string
---@param root string?
---@return string
local function rel_path(path, root)
  if not root then
    return path
  end
  root = vim.fs.normalize(root):gsub("/+$", "")
  path = vim.fs.normalize(path)
  if vim.startswith(path, root .. "/") then
    return path:sub(#root + 2)
  end
  return path
end

---Resolve a wiki/markdown link target to absolute paths in `notes`.
---@param target string e.g. "bar", "subdir/bar", "subdir/bar.md"
---@param notes table<string, table>
---@param opts { root: string? }?
---@return string[]
function M.resolve(target, notes, opts)
  opts = opts or {}
  if target == "" or util.is_uri(target) then
    return {}
  end

  local stripped = target:gsub("%.md$", "")
  local hits = {}
  for path, _ in pairs(notes) do
    local rel = rel_path(path, opts.root)
    if basename(path) == stripped or rel == target or rel == stripped .. ".md" then
      hits[#hits + 1] = path
    end
  end
  table.sort(hits)
  return hits
end

---Build backlinks for `target_path` from note rows with `links_out` arrays.
---@param target_path string
---@param notes table<string, { links_out: table[]? }>
---@param opts { root: string? }?
---@return { source: string, link: table }[]
function M.build_for(target_path, notes, opts)
  local out = {}
  for src_path, note in pairs(notes) do
    if src_path ~= target_path then
      for _, link in ipairs(note.links_out or {}) do
        for _, resolved in ipairs(M.resolve(link.target, notes, opts)) do
          if resolved == target_path then
            out[#out + 1] = { source = src_path, link = link }
            break
          end
        end
      end
    end
  end

  table.sort(out, function(a, b)
    if a.source == b.source then
      return (a.link.line or 0) < (b.link.line or 0)
    end
    return a.source < b.source
  end)
  return out
end

return M
