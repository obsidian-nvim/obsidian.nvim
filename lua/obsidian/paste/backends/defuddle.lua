local async = require "obsidian.async"
local http = require "obsidian.http"
local Note = require "obsidian.note"

local M = {}

M.endpoint = "https://defuddle.md/"

---Whether the local `defuddle` CLI is available.
---@return boolean
M.has_cli = function()
  return vim.fn.executable "defuddle" == 1
end

---@class obsidian.defuddle.Result
---@field markdown string
---@field metadata table<string, any>|? decoded JSON metadata, only present when `opts.json` is set

---Run `defuddle parse` on a source (file path or URL).
---
---@param source string file path or URL
---@param opts { json: boolean|? }
---@param callback fun(result: obsidian.defuddle.Result?, err: string?)
---@param on_done fun()|? cleanup hook, runs before the callback
---@return any job
local function run_cli(source, opts, callback, on_done)
  local cmd = { "defuddle", "parse", source, "--markdown" }
  if opts.json then
    table.insert(cmd, "--json")
  end

  local lines = {}
  return async.run_job_async(cmd, function(line)
    table.insert(lines, line)
  end, function(code)
    if on_done then
      on_done()
    end

    local out = table.concat(lines, "\n")
    if code ~= 0 or out == "" then
      callback(nil, ("defuddle CLI failed (%d)"):format(code))
      return
    end

    if not opts.json then
      callback({ markdown = out }, nil)
      return
    end

    local ok, decoded = pcall(vim.json.decode, out)
    if not ok or type(decoded) ~= "table" then
      callback(nil, "failed to decode defuddle CLI JSON output")
      return
    end

    local markdown = decoded.content
    if type(markdown) ~= "string" then
      callback(nil, "defuddle CLI JSON output did not include content")
      return
    end

    decoded.content = nil
    callback({ markdown = markdown, metadata = decoded }, nil)
  end)
end

---Convert a string of HTML to markdown with the local `defuddle` CLI.
---
---The published CLI only reads from a file path or URL, so the HTML string is
---written to a temporary file first.
---
---With `opts.json` the result also carries the page metadata
---(title, description, author, published, domain, ...).
---
---@param html string
---@param opts { json: boolean|? }|?
---@param callback fun(result: obsidian.defuddle.Result?, err: string?)
---@return any job
M.convert_async = function(html, opts, callback)
  opts = opts or {}

  if not M.has_cli() then
    callback(nil, "defuddle CLI is not executable, install it with `npm install -g defuddle`")
    return
  end

  local tmp = vim.fn.tempname() .. ".html"
  local fd = io.open(tmp, "w")
  if not fd then
    callback(nil, "failed to write temporary html file " .. tmp)
    return
  end
  fd:write(html)
  fd:close()

  return run_cli(tmp, opts, callback, function()
    os.remove(tmp)
  end)
end

---@param markdown string
---@return obsidian.Note
M.note_from_markdown = function(markdown)
  local lines = vim.split(markdown, "\n")
  return Note.from_lines(lines, nil, {})
end

---@param markdown string|nil
---@return string|nil
M.title_from_markdown = function(markdown)
  if not markdown or markdown == "" then
    return nil
  end

  return M.note_from_markdown(markdown).metadata.title
end

---Fetch a URL and convert it to markdown with a YAML frontmatter header.
---
---Prefers the local `defuddle` CLI when available (no web service round-trip),
---falling back to the defuddle.md endpoint otherwise.
---
---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(markdown:string?, err:string?)
---@return any job
M.fetch_markdown_async = function(url, opts, callback)
  if M.has_cli() then
    return run_cli(url, { json = true }, function(result, err)
      if not result then
        callback(nil, err)
        return
      end

      local metadata = result.metadata or {}
      metadata.source = url
      -- lazy require to avoid a circular dependency (webpage requires defuddle)
      local header = require("obsidian.webpage").frontmatter(metadata)
      callback(header .. "\n\n" .. result.markdown, nil)
    end)
  end

  return http.fetch_async(M.endpoint .. url, opts, function(markdown, err)
    callback(markdown, err)
  end)
end

---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(note:obsidian.Note?, err:string?)
---@return any job
M.fetch_note_async = function(url, opts, callback)
  return M.fetch_markdown_async(url, opts, function(markdown, err)
    if not markdown then
      callback(nil, err)
      return
    end

    callback(M.note_from_markdown(markdown), nil)
  end)
end

---@param url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(title:string?, err:string?)
---@return any job
M.fetch_title_async = function(url, opts, callback)
  return M.fetch_markdown_async(url, opts, function(markdown, err)
    if not markdown then
      callback(nil, err)
      return
    end

    local title = M.title_from_markdown(markdown)
    if not title then
      callback(nil, "defuddle response did not include a title")
      return
    end

    callback(title, nil)
  end)
end

return M
