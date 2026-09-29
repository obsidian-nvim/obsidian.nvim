local Path = require "obsidian.path"
local async = require "obsidian.async"
local SearchOpts = require "obsidian.search.opts"
local api = require "obsidian.api"
local filetypes = require "obsidian.filetypes"
local fs_util = require "obsidian.util.fs"
local fs = require "obsidian.fs"
local gitignore = require("obsidian.lib.glob").gitignore

local M = {}

local BASE_CMD = {
  "rg",
  "--no-config",
  "--type-add",
  "md:*.qmd",
  "--type-add",
  "md:*.base",
}

-- `--crlf` makes ripgrep treat `\r\n` as a line terminator so that `$`
-- anchors in search patterns (e.g. frontmatter tag lists) also match files
-- with DOS line endings. See https://github.com/obsidian-nvim/obsidian.nvim/issues/903.
---@diagnostic disable-next-line: call-non-callable
local SEARCH_CMD = vim.iter({ BASE_CMD, "--type=md", "--json", "--crlf" }):flatten():totable()
---@diagnostic disable-next-line: call-non-callable
local FIND_CMD = vim.iter({ BASE_CMD, "--files" }):flatten():totable()

---@param opts obsidian.search.BackendOpts
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
---@param opts obsidian.search.BackendOpts|?
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

  ---@diagnostic disable-next-line: call-non-callable
  return vim
    .iter({
      SEARCH_CMD,
      generate_args(opts),
      search_terms,
      path,
    })
    :flatten()
    :totable()
end

---@param path string?
---@param opts obsidian.search.BackendOpts?
---@return string[]
M.build_find_cmd = function(path, opts)
  opts = vim.tbl_extend("keep", opts or {}, { ignore_case = true })

  local additional_opts = {}
  if not opts.include_non_markdown then
    additional_opts[#additional_opts + 1] = "--type=md"
  end

  if path ~= nil and path ~= "." then
    additional_opts[#additional_opts + 1] = path
  end

  ---@diagnostic disable-next-line: call-non-callable
  return vim
    .iter({
      FIND_CMD,
      generate_args(opts),
      additional_opts,
    })
    :flatten()
    :totable()
end

--- Build the 'rg' grep command for pickers.
---
---@param opts obsidian.search.BackendOpts|?
---
---@return string[]
M.build_grep_cmd = function(opts)
  opts = vim.tbl_extend("keep", opts or {}, {
    smart_case = true,
    fixed_strings = true,
  })

  ---@diagnostic disable-next-line: call-non-callable
  return vim
    .iter({
      BASE_CMD,
      "--type=md",
      generate_args(opts),
      "--column",
      "--line-number",
      "--no-heading",
      "--with-filename",
      "--color=never",
    })
    :flatten()
    :totable()
end

--- Search Markdown files with ripgrep. Each match is passed to `on_match`.
---
---@param dir string|obsidian.Path
---@param term string|string[]
---@param opts obsidian.search.BackendOpts|?
---@param on_match fun(match: MatchData)
---@param on_exit fun(exit_code: integer)|?
---@return vim.SystemObj handle
M.search_async = function(dir, term, opts, on_match, on_exit)
  opts = SearchOpts.resolve(dir, opts)
  local cmd = M.build_search_cmd(dir, term, opts)
  return async.run_job_async(cmd, function(line)
    local data = vim.json.decode(line)
    if data["type"] == "match" then
      on_match(data.data)
    end
  end, function(code)
    if on_exit then
      on_exit(code)
    end
  end)
end

M._has_ripgrep = function()
  return vim.fn.executable "rg" == 1
end

--- Find files in a directory matching a given term. Each matching path is
--- passed to the `on_match` callback. Falls back to Neovim's filesystem APIs
--- when ripgrep is unavailable or fails.
---
---@param dir string|obsidian.Path
---@param term string?
---@param opts obsidian.search.BackendOpts|?
---@param on_match fun(path: string)
---@param on_exit fun(exit_code: integer)|?
---@return fun() cancel
M.find_async = function(dir, term, opts, on_match, on_exit)
  local norm_dir = Path.new(dir):resolve { strict = true }
  opts = SearchOpts.resolve(norm_dir, opts)

  local query = term and string.lower(term) or nil
  local exclude = opts.exclude and gitignore(opts.exclude, { ignoreCase = true }) or nil
  local markdown_extensions = { [".md"] = true, [".qmd"] = true, [".base"] = true }

  local cancelled = false
  local cancel_backend

  local function finish(paths, code)
    if cancelled then
      return
    end
    for _, path in ipairs(paths) do
      on_match(vim.fs.normalize(path))
    end
    if on_exit ~= nil then
      on_exit(code)
    end
  end

  local function find_with_fs()
    cancel_backend = fs.find_files_async(norm_dir, {
      sort_by = opts.sort_by,
      sort_reversed = opts.sort_reversed,
      ignore = function(path)
        if not exclude then
          return false
        end
        local relative_path = tostring(Path.new(path):relative_to(norm_dir))
        return exclude:check(relative_path)
      end,
      predicate = function(path)
        local extension = "." .. vim.fn.fnamemodify(path, ":e"):lower()
        if not opts.include_non_markdown and not markdown_extensions[extension] then
          return false
        end
        return not query or string.find(string.lower(vim.fs.basename(path)), query, 1, true) ~= nil
      end,
    }, function(paths)
      finish(paths, 0)
    end)
  end

  if M._has_ripgrep() then
    local handle = vim.system(M.build_find_cmd(tostring(norm_dir), opts), { text = true }, function(result)
      vim.schedule(function()
        if cancelled then
          return
        elseif result.code ~= 0 then
          find_with_fs()
          return
        end

        local paths = vim
          .iter(vim.split(result.stdout or "", "\n", { plain = true, trimempty = true }))
          :filter(function(path)
            if query then
              return string.find(string.lower(vim.fs.basename(path)), query, 1, true) ~= nil
            else
              return true
            end
          end)
          :totable()

        finish(paths, result.code)
      end)
    end)
    cancel_backend = function()
      handle:kill(15)
    end
  else
    find_with_fs()
  end

  return function()
    cancelled = true
    if cancel_backend then
      cancel_backend()
    end
  end
end

---Find attachment paths matching a filename or vault-relative path.
---@param term string
---@param callback fun(paths: string[])
---@param opts obsidian.search.FindAttachmentsOpts|?
M.find_attachments_async = function(term, callback, opts)
  callback = vim.schedule_wrap(callback)
  opts = opts or {}
  local dir = opts.dir or api.resolve_workspace_dir()

  local paths = {}
  local query = vim.trim(term or "")
  local ignore_case = SearchOpts.should_ignore_case(query)
  if ignore_case then
    query = query:lower()
  end
  return M.find_async(dir, nil, {
    sort_by = opts.sort_by,
    sort_reversed = opts.sort_reversed,
    include_non_markdown = true,
  }, function(path)
    if filetypes.is_attachment(path) then
      local rel = fs_util.relpath(tostring(dir), path) or path
      if ignore_case then
        rel = rel:lower()
      end
      if query == "" or rel:find(query, 1, true) then
        paths[#paths + 1] = path
      end
    end
  end, function()
    callback(paths)
  end)
end

return M
