local Path = require "obsidian.path"
local util = require "obsidian.util"
local search_files = require "obsidian.search.files"

local M = {}

local BASE_CMD = {
  "rg",
  "--no-config",
}

local function extension_args()
  local args = {}
  for _, glob in ipairs(search_files.ripgrep_globs()) do
    args[#args + 1] = "--glob=" .. glob
  end
  return args
end

-- `--crlf` makes ripgrep treat `\r\n` as a line terminator so that `$`
-- anchors in search patterns (e.g. frontmatter tag lists) also match files
-- with DOS line endings. See https://github.com/obsidian-nvim/obsidian.nvim/issues/903.
local SEARCH_CMD = util.flatten { BASE_CMD, extension_args(), "--json", "--crlf" }
local FIND_CMD = util.flatten { BASE_CMD, "--files" }

---@param opts obsidian.search.SearchOpts
---@return string[]
local generate_args = function(opts)
  -- vim.validate("opts.exclude", opts.exclude, "table", true)

  local ret = {}

  if opts.sort_by then
    local sort = "sortr" -- default sort is reverse
    if opts.sort_reversed == false then
      sort = "sort"
    end
    ret[#ret + 1] = "--" .. sort .. "=" .. opts.sort_by
  end

  if opts.fixed_strings then
    ret[#ret + 1] = "--fixed-strings"
  end

  if opts.ignore_case then
    ret[#ret + 1] = "--ignore-case"
  end

  if opts.smart_case then
    ret[#ret + 1] = "--smart-case"
  end

  if opts.exclude ~= nil then
    for _, path in ipairs(opts.exclude) do
      ret[#ret + 1] = "-g!" .. path
    end
  end

  if opts.max_count_per_file ~= nil then
    ret[#ret + 1] = "-m=" .. opts.max_count_per_file
  end

  return ret
end

M._generate_args = generate_args

---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_search_cmd = function(dir, term, opts)
  opts = opts and opts or {}

  local search_terms
  if type(term) == "string" then
    search_terms = { "-e", term }
  else
    search_terms = {}
    for _, t in ipairs(term) do
      search_terms[#search_terms + 1] = "-e"
      search_terms[#search_terms + 1] = t
    end
  end

  local path = tostring(Path.new(dir):resolve { strict = true })
  if opts.escape_path then
    path = vim.fn.fnameescape(path)
  end

  return util.flatten {
    SEARCH_CMD,
    generate_args(opts),
    search_terms,
    path,
  }
end

---@param path string?
---@param opts obsidian.search.SearchOpts?
---@return string[]
M.build_find_cmd = function(path, opts)
  opts = opts or {}
  local search_opts = Obsidian and Obsidian.opts and Obsidian.opts.search or {}
  opts = vim.tbl_extend("keep", opts, {
    sort_by = search_opts.sort_by,
    sort_reversed = search_opts.sort_reversed,
    ignore_case = true,
  })

  local additional_opts = {}
  if not opts.include_non_markdown then
    vim.list_extend(additional_opts, extension_args())
  end

  if path ~= nil and path ~= "." then
    additional_opts[#additional_opts + 1] = path
  end

  return util.flatten {
    FIND_CMD,
    generate_args(opts),
    additional_opts,
  }
end

--- Build the 'rg' grep command for pickers.
---
---@param opts obsidian.search.SearchOpts|?
---
---@return string[]
M.build_grep_cmd = function(opts)
  opts = opts and opts or {}
  local search_opts = Obsidian and Obsidian.opts and Obsidian.opts.search or {}

  opts = vim.tbl_extend("keep", opts, {
    sort_by = search_opts.sort_by,
    sort_reversed = search_opts.sort_reversed,
    smart_case = true,
    fixed_strings = true,
  })

  return util.flatten {
    BASE_CMD,
    extension_args(),
    generate_args(opts),
    "--column",
    "--line-number",
    "--no-heading",
    "--with-filename",
    "--color=never",
  }
end

---@class obsidian.search.ReadLinesResult
---@field lines table<string, string[]>

---Read complete lines for an explicit cache-defined set of paths through
---ripgrep JSON. `^` deliberately matches every logical line, including blank
---lines, so this is a content transport rather than a filesystem index.
---@param paths string[]
---@param callback fun(result: obsidian.search.ReadLinesResult|nil, err: string|nil)
---@param opts { chunk_size: integer|nil, max_jobs: integer|nil }|nil
---@return fun() cancel
function M.read_lines_async(paths, callback, opts)
  opts = opts or {}
  local chunk_size = opts.chunk_size or 128
  local max_jobs = opts.max_jobs or 4
  local cancelled = false
  local handles = {}
  local lines = {}

  for _, path in ipairs(paths) do
    lines[vim.fs.normalize(path)] = {}
  end

  if #paths == 0 then
    vim.schedule(function()
      if not cancelled then
        callback({ lines = lines }, nil)
      end
    end)
    return function()
      cancelled = true
    end
  end

  local chunks = {}
  for first = 1, #paths, chunk_size do
    chunks[#chunks + 1] = vim.list_slice(paths, first, math.min(#paths, first + chunk_size - 1))
  end

  local finished = false
  local remaining = #chunks
  local active = 0
  local next_chunk = 1
  local function fail(err)
    if finished or cancelled then
      return
    end
    finished = true
    for _, handle in ipairs(handles) do
      pcall(handle.kill, handle, 15)
    end
    callback(nil, err)
  end

  local start_jobs = function() end
  local function finish_one()
    active = active - 1
    remaining = remaining - 1
    if remaining == 0 and not finished and not cancelled then
      finished = true
      callback({ lines = lines }, nil)
    elseif not finished and not cancelled then
      start_jobs()
    end
  end

  start_jobs = function()
    while active < max_jobs and next_chunk <= #chunks and not cancelled and not finished do
      local paths_chunk = chunks[next_chunk]
      next_chunk = next_chunk + 1
      active = active + 1
      local cmd = util.flatten {
        BASE_CMD,
        "--json",
        "--line-number",
        "--color=never",
        "-e",
        "^",
        "--",
        paths_chunk,
      }
      local handle = vim.system(cmd, { text = true }, function(result)
        vim.schedule(function()
          if cancelled or finished then
            return
          end
          if result.code ~= 0 and result.code ~= 1 then
            local message = vim.trim(result.stderr or "")
            if message == "" then
              message = "ripgrep failed with exit code " .. result.code
            end
            fail(message)
            return
          end
          for _, json_line in ipairs(vim.split(result.stdout or "", "\n", { plain = true, trimempty = true })) do
            local ok, event = pcall(vim.json.decode, json_line)
            if ok and event.type == "match" then
              local data = event.data
              local path = vim.fs.normalize(data.path.text)
              local text = (data.lines.text or ""):gsub("\r?\n$", "")
              lines[path] = lines[path] or {}
              lines[path][data.line_number] = text
            end
          end
          finish_one()
        end)
      end)
      handles[#handles + 1] = handle
    end
  end

  start_jobs()

  return function()
    if cancelled then
      return
    end
    cancelled = true
    for _, handle in ipairs(handles) do
      pcall(handle.kill, handle, 15)
    end
  end
end

return M
