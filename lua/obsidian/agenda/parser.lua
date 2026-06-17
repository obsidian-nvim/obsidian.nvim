local dates = require "obsidian.agenda.dates"

local M = {}

---@param text string
---@return string[]
local function parse_tags(text)
  local tags = {}
  for tag in text:gmatch "#([%w_/%-]+)" do
    tags[#tags + 1] = tag
  end
  return tags
end

---@param body string
---@return obsidian.agenda.Priority?
local function parse_priority(body)
  local priority = body:match "%[#([ABC])%]"
  ---@cast priority obsidian.agenda.Priority|nil
  return priority
end

---@param body string
---@return integer?, integer?, integer?, integer?
local function parse_dates(body)
  local date, due, scheduled, done

  for name, value in body:gmatch "@([%a_]+)%((%d%d%d%d%-%d%d?%-%d%d?)%)" do
    local parsed = dates.parse(value)
    if name == "due" then
      due = parsed
    elseif name == "scheduled" then
      scheduled = parsed
    elseif name == "done" then
      done = parsed
    end
  end

  for value in body:gmatch "@(%d%d%d%d%-%d%d?%-%d%d?)" do
    date = date or dates.parse(value)
  end

  return date, due, scheduled, done
end

---@param body string
---@return string
local function clean_title(body)
  local title = body
  title = title:gsub("@[%a_]+%(%d%d%d%d%-%d%d?%-%d%d?%)", "")
  title = title:gsub("@%d%d%d%d%-%d%d?%-%d%d?", "")
  title = title:gsub("%[#[ABC]%]", "")
  title = title:gsub("%s+", " ")
  return vim.trim(title)
end

---@param line string
---@param opts? obsidian.agenda.ParseOpts
---@return obsidian.agenda.Item?
M.parse_line = function(line, opts)
  opts = opts or {}

  local start_pos, end_pos, marker, rest = line:find "^%s*[-*+] %[(.)%]%s*(.*)$"
  if not start_pos then
    return nil
  end

  ---@cast marker string
  ---@cast rest string
  ---@type obsidian.agenda.ItemStatus
  local status = (marker == "x" or marker == "X") and "done" or "todo"
  local date, due, scheduled, done = parse_dates(rest)
  local checkbox_col = assert(line:find("%[" .. vim.pesc(marker) .. "%]", 1) or end_pos)

  ---@type obsidian.agenda.Item
  local item = {
    id = table.concat({ opts.path or "", tostring(opts.lnum or 0), rest }, ":"),
    title = clean_title(rest),
    status = status,
    checkbox = marker,
    path = opts.path,
    lnum = opts.lnum,
    col = 1,
    checkbox_col = checkbox_col + 1,
    date = date,
    due = due,
    scheduled = scheduled,
    done = done,
    priority = parse_priority(rest),
    tags = parse_tags(rest:gsub("%[#[ABC]%]", "")),
    raw = line,
    source = opts.source or "markdown",
    metadata = {},
  }

  return item
end

---@param lines string[]
---@param opts? obsidian.agenda.ParseOpts
---@return obsidian.agenda.Item[]
M.parse_lines = function(lines, opts)
  opts = opts or {}
  local items = {}
  for i, line in ipairs(lines) do
    local item = M.parse_line(line, {
      path = opts.path,
      lnum = i,
      source = opts.source,
    })
    if item then
      items[#items + 1] = item
    end
  end
  return items
end

---@param path string|obsidian.Path
---@param opts? obsidian.agenda.ParseOpts
---@return obsidian.agenda.Item[]
M.parse_file = function(path, opts)
  opts = opts or {}
  local ok, lines = pcall(vim.fn.readfile, tostring(path))
  if not ok then
    return {}
  end
  return M.parse_lines(lines, { path = tostring(path), source = opts.source or "file" })
end

return M
