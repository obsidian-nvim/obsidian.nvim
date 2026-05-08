local M = {}

---@alias obsidian.textobj.LinkType
---| "Wiki"
---| "WikiAlias"
---| "Markdown"
---| "Attachment"

---@type { name: obsidian.textobj.LinkType, pat: string }[]
local PATTERNS = {
  { name = "Attachment", pat = "!%[[^][]*%]%([^%)]+%)" },
  { name = "WikiAlias", pat = "%[%[[^][%|]+%|[^%]]+%]%]" },
  { name = "Wiki", pat = "%[%[[^][%|]+%]%]" },
  { name = "Markdown", pat = "%[[^][]*%]%([^%)]+%)" },
}

---@class obsidian.textobj.LinkMatch
---@field type obsidian.textobj.LinkType
---@field start integer 1-indexed byte position (inclusive)
---@field finish integer 1-indexed byte position (inclusive)
---@field text string
---@field row integer 1-indexed buffer row

---@param line string
---@param col integer 1-indexed byte column of cursor
---@return { type: obsidian.textobj.LinkType, start: integer, finish: integer, text: string }|nil
local function find_in_line(line, col)
  ---@type { type: obsidian.textobj.LinkType, start: integer, finish: integer, text: string }[]
  local matches = {}
  for _, p in ipairs(PATTERNS) do
    local pos = 1
    while pos <= #line do
      local s, e = string.find(line, p.pat, pos)
      if not s or not e then
        break
      end
      matches[#matches + 1] = { type = p.name, start = s, finish = e, text = line:sub(s, e) }
      pos = e + 1
    end
  end
  if #matches == 0 then
    return nil
  end
  -- pick the longest match containing the cursor; outer match wins over inner
  ---@type { type: obsidian.textobj.LinkType, start: integer, finish: integer, text: string }|nil
  local best
  for _, m in ipairs(matches) do
    if col >= m.start and col <= m.finish then
      if not best or (m.finish - m.start) > (best.finish - best.start) then
        best = m
      end
    end
  end
  return best
end

---@return obsidian.textobj.LinkMatch|nil
local function find_link_at_cursor()
  local line = vim.api.nvim_get_current_line()
  local row, col0 = unpack(vim.api.nvim_win_get_cursor(0))
  local m = find_in_line(line, col0 + 1)
  if not m then
    return nil
  end
  return {
    type = m.type,
    start = m.start,
    finish = m.finish,
    text = m.text,
    row = row,
  }
end

---@param row integer 1-indexed
---@param start_col integer 1-indexed inclusive
---@param finish_col integer 1-indexed inclusive
---@param replacement string
local function replace(row, start_col, finish_col, replacement)
  vim.api.nvim_buf_set_text(0, row - 1, start_col - 1, row - 1, finish_col, { replacement })
end

---@param target string
---@return boolean deleted
local function maybe_delete_attachment(target)
  local attachment = require "obsidian.attachment"
  if not attachment.is_attachment_path(target) then
    return false
  end
  local path = attachment.resolve_attachment_path(target)
  if vim.fn.filereadable(path) ~= 1 then
    return false
  end
  local choice = vim.fn.confirm("Delete attachment file?\n" .. path, "&Yes\n&No", 2)
  if choice == 1 then
    local ok, err = pcall(vim.fn.delete, path)
    if not ok then
      require("obsidian.log").err("Failed to delete %s: %s", path, err)
      return false
    end
    return true
  end
  return false
end

---Transform link under cursor: strip wiki/markdown wrapping, autolink external URL,
---prompt to delete attachment files.
M.transform_link = function()
  local link = find_link_at_cursor()
  if not link then
    return
  end

  local util = require "obsidian.util"

  if link.type == "Wiki" then
    local loc = link.text:sub(3, #link.text - 2)
    replace(link.row, link.start, link.finish, util.strip_anchor_links(util.strip_block_links(loc)))
  elseif link.type == "WikiAlias" then
    local inner = link.text:sub(3, #link.text - 2)
    local idx = inner:find "|"
    local name = inner:sub(idx + 1)
    replace(link.row, link.start, link.finish, name)
  elseif link.type == "Markdown" then
    local name = link.text:match "%[(.-)%]"
    local target = link.text:match "%((.-)%)"
    if util.is_uri(target) then
      replace(link.row, link.start, link.finish, "<" .. target .. ">")
    else
      local replacement = name ~= "" and name or util.strip_anchor_links(util.strip_block_links(target))
      replace(link.row, link.start, link.finish, replacement)
    end
  elseif link.type == "Attachment" then
    local target = link.text:match "%((.-)%)"
    maybe_delete_attachment(target)
    replace(link.row, link.start, link.finish, "")
  end
end

-- Operatorfunc shim so `.` repeats the transform.
-- See https://vikasraj.dev/blog/vim-dot-repeat
M._opfunc = function()
  M.transform_link()
end

---Expression mapping: sets operatorfunc and returns `g@l` so the user's keypress
---becomes a single operator invocation that the dot register can replay.
---@return string
M.dl_expr = function()
  vim.go.operatorfunc = "v:lua.require'obsidian.textobj'._opfunc"
  return "g@l"
end

return M
