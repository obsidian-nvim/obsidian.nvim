local Path = require "obsidian.path"
local parser = require "obsidian.agenda.parser"

local M = {}

---@param item obsidian.agenda.Item
---@return obsidian.agenda.Item
local function normalize_item(item)
  item.status = item.status or "todo"
  item.tags = item.tags or {}
  item.metadata = item.metadata or {}
  item.id = item.id
    or table.concat({ item.source or "custom", item.path or "", tostring(item.lnum or ""), item.title or "" }, ":")
  return item
end

---@param items obsidian.agenda.Item[]|nil
---@return obsidian.agenda.Item[]
M.normalize_items = function(items)
  local out = {}
  for _, item in ipairs(items or {}) do
    if item.title and item.title ~= "" then
      out[#out + 1] = normalize_item(item)
    end
  end
  return out
end

---@return obsidian.Path
M.default_file = function()
  local file = Obsidian.opts.agenda.file or "agenda.md"
  local path = Path.new(file)
  if path:is_absolute() then
    return path
  end
  return Path.new(Obsidian.dir) / file
end

---@class obsidian.agenda.SourceContext
---@field parse_lines fun(lines: string[], opts: table|?): obsidian.agenda.Item[]
---@field parse_markdown_file fun(path: string|obsidian.Path, opts: table|?): obsidian.agenda.Item[]
---@field default_file fun(): obsidian.Path

---@return obsidian.agenda.SourceContext
M.context = function()
  return {
    parse_lines = parser.parse_lines,
    parse_markdown_file = parser.parse_file,
    default_file = M.default_file,
  }
end

---@param done fun(items: obsidian.agenda.Item[]|nil, err: string|nil)
---@return any handle
local function collect_default(done)
  return vim.schedule(function()
    local items = parser.parse_file(M.default_file())
    done(M.normalize_items(items), nil)
  end)
end

---@param done fun(items: obsidian.agenda.Item[]|nil, err: string|nil)
---@return any handle
M.collect = function(done)
  local get_items = Obsidian.opts.agenda.get_items
  if type(get_items) ~= "function" then
    return collect_default(done)
  end

  local called = false
  local function finish(items, err)
    if called then
      return
    end
    called = true
    if err then
      done(nil, err)
    else
      done(M.normalize_items(items), nil)
    end
  end

  local ok, result = pcall(get_items, M.context(), finish)
  if not ok then
    finish(nil, result)
    return
  end

  if type(result) == "table" and type(result.kill) ~= "function" then
    finish(result, nil)
  end

  return result
end

return M
