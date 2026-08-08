local fs = require "obsidian.fs"
local parse_tags = require "obsidian.parse.tags"
local Path = require "obsidian.path"
local yaml = require "obsidian.yaml"

local M = {}

---@param value any
---@param out   string[]
local function flatten(value, out)
  if value == vim.NIL or value == nil then
    return
  elseif type(value) == "table" then
    for key, item in pairs(value) do
      if not vim.islist(value) then
        out[#out + 1] = tostring(key)
      end
      flatten(item, out)
    end
  else
    out[#out + 1] = tostring(value)
  end
end

---@param lines string[]
---@return table<string, any>
local function parse_properties(lines)
  if lines[1] == nil or not lines[1]:match "^%-%-%-+%s*$" then
    return {}
  end
  local frontmatter = {}
  for i = 2, #lines do
    if lines[i]:match "^%-%-%-+%s*$" then
      local ok, properties = pcall(yaml.loads, table.concat(frontmatter, "\n"))
      return ok and type(properties) == "table" and properties or {}
    end
    frontmatter[#frontmatter + 1] = lines[i]
  end
  return {}
end

---@param lines string[]
---@return { text: string, line: integer } []
local function collect_tags(lines)
  local tags = {}
  local fence
  for line_number, line in ipairs(lines) do
    local marker = line:match "^%s*(```+)" or line:match "^%s*(~~~+)"
    if marker then
      if not line:match "^%s*[`~][`~][`~].*[`~][`~][`~]%s*$" then
        if not fence then
          fence = marker:sub(1, 1)
        elseif marker:sub(1, 1) == fence then
          fence = nil
        end
      end
    elseif not fence then
      for _, match in ipairs(parse_tags.extract(line, { row = line_number - 1 })) do
        tags[#tags + 1] = { text = "#" .. match.tag, line = line_number }
      end
    end
  end

  local frontmatter_tags = parse_properties(lines).tags
  if frontmatter_tags ~= nil then
    local values = {}
    flatten(frontmatter_tags, values)
    for _, tag in ipairs(values) do
      tags[#tags + 1] = { text = vim.startswith(tag, "#") and tag or "#" .. tag, line = 1 }
    end
  end
  return tags
end

---@param path  string | obsidian.Path
---@param lines string[]
---@param opts  { root: string | obsidian.Path |? } |?
---@return obsidian.search.QueryDocument
function M.from_lines(path, lines, opts)
  opts = opts or {}
  path = vim.fs.normalize(tostring(path))
  local relative_path = path
  if opts.root then
    local ok, relative = pcall(function()
      return tostring(Path.new(path):relative_to(opts.root))
    end)
    if ok then
      relative_path = relative
    end
  end
  return {
    path = path,
    relative_path = relative_path,
    filename = vim.fs.basename(path),
    lines = lines,
    properties = parse_properties(lines),
    tags = collect_tags(lines),
  }
end

---@param path string | obsidian.Path
---@param opts { root: string | obsidian.Path |? } |?
---@return obsidian.search.QueryDocument
function M.from_file(path, opts)
  return M.from_lines(path, vim.fn.readfile(tostring(path)), opts)
end

local searchable_extensions = { base = true, canvas = true, md = true, qmd = true }

---@param path     string
---@param callback fun(data: string |?)
local function read_file_async(path, callback)
  vim.uv.fs_open(path, "r", 438, function(open_error, fd)
    if open_error or not fd then
      vim.schedule(function()
        callback(nil)
      end)
      return
    end
    vim.uv.fs_fstat(fd, function(stat_error, stat)
      if stat_error or not stat then
        vim.uv.fs_close(fd)
        vim.schedule(function()
          callback(nil)
        end)
        return
      end
      vim.uv.fs_read(fd, stat.size, 0, function(read_error, data)
        vim.uv.fs_close(fd)
        vim.schedule(function()
          callback(read_error and nil or data)
        end)
      end)
    end)
  end)
end

---@param dir      string | obsidian.Path
---@param opts     { include_non_markdown: boolean |?, concurrency: integer |? } |?
---@param callback fun(documents: obsidian.search.QueryDocument[])
---@return fun() cancel
function M.index_async(dir, opts, callback)
  opts = opts or {}
  local root = Path.new(dir):resolve { strict = true }
  local cancelled = false
  local paths = {}
  local cancel_find = fs.find_files_async(root, {
    sort_by = "path",
    predicate = function(path)
      local extension = vim.fn.fnamemodify(path, ":e"):lower()
      return opts.include_non_markdown or searchable_extensions[extension] == true
    end,
  }, function(found)
    if cancelled then
      return
    end
    paths = found
    if #paths == 0 then
      callback {}
      return
    end

    local documents = {}
    local next_index = 1
    local remaining = #paths
    local workers = math.min(opts.concurrency or 16, #paths)

    local function finish(index, data)
      if cancelled then
        return
      end
      local path = assert(paths[index], "indexed path is missing")
      local lines = data and vim.split(data, "\n", { plain = true }) or {}
      documents[index] = M.from_lines(path, lines, { root = root })
      remaining = remaining - 1
      if remaining == 0 then
        callback(documents)
        return
      end

      local queued = next_index
      next_index = next_index + 1
      if queued <= #paths then
        read_file_async(assert(paths[queued], "queued path is missing"), function(next_data)
          finish(queued, next_data)
        end)
      end
    end

    for _ = 1, workers do
      local index = next_index
      next_index = next_index + 1
      read_file_async(assert(paths[index], "indexed path is missing"), function(data)
        finish(index, data)
      end)
    end
  end)

  return function()
    cancelled = true
    if cancel_find then
      cancel_find()
    end
  end
end

return M
