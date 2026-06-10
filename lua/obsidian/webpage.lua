local defuddle = require "obsidian.paste.backends.defuddle"
local html = require "obsidian.html"
local http = require "obsidian.http"
local url = require "obsidian.url"
local yaml = require "obsidian.yaml"

local M = {}

local frontmatter_keys = { "title", "source", "author", "published", "created", "description" }

local key_priority = {}
for i, key in ipairs(frontmatter_keys) do
  key_priority[key] = i
end

local function key_order(a, b)
  local pa, pb = key_priority[a] or math.huge, key_priority[b] or math.huge
  if pa ~= pb then
    return pa < pb
  end
  return tostring(a) < tostring(b)
end

---Build a YAML frontmatter header from page metadata, mirroring the
---Obsidian web clipper's default note properties.
---
---Empty values and non-string values (e.g. vim.NIL from decoded JSON) are skipped.
---
---@param metadata table<string, any> e.g. { title = ..., source = ..., author = ..., published = ..., description = ... }
---@return string header including the `---` delimiters, no trailing newline
M.frontmatter = function(metadata)
  local fields = {}
  for _, key in ipairs(frontmatter_keys) do
    local value = metadata[key]
    if type(value) == "string" and vim.trim(value) ~= "" then
      fields[key] = vim.trim(value)
    end
  end

  if not fields.created then
    fields.created = os.date "%Y-%m-%d"
  end

  local lines = { "---" }
  vim.list_extend(lines, yaml.dumps_lines(fields, key_order))
  table.insert(lines, "---")
  return table.concat(lines, "\n")
end

---Convert a string of HTML (a full webpage) into a note with a YAML
---frontmatter header.
---
---@param page_html string
---@param opts { url: string|?, backend: obsidian.html.Backend|? }|?
---@param callback fun(note: obsidian.Note?, err: string?)
---@return any job
M.note_from_html_async = function(page_html, opts, callback)
  opts = opts or {}
  return html.to_markdown_async(
    page_html,
    { mode = "page", url = opts.url, backend = opts.backend },
    function(markdown, err)
      if not markdown then
        callback(nil, err)
        return
      end

      callback(defuddle.note_from_markdown(markdown), nil)
    end
  )
end

---@param page_url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(html:string?, err:string?)
---@return any job
M.fetch_html_async = function(page_url, opts, callback)
  return http.fetch_async(page_url, opts, function(body, err)
    callback(body, err)
  end)
end

---@param page_url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(title:string?, err:string?)
---@return any job
M.fetch_html_title_async = function(page_url, opts, callback)
  return M.fetch_html_async(page_url, opts, function(body, err)
    if not body then
      callback(nil, err)
      return
    end

    local title = html.title_from_html(body)
    if not title then
      callback(nil, "html response did not include a title")
      return
    end

    callback(title, nil)
  end)
end

---@param page_url string
---@param opts obsidian.http.FetchOpts|?
---@param callback fun(title:string, source:"defuddle"|"html"|"url")
---@return any job
M.title_from_url_async = function(page_url, opts, callback)
  return defuddle.fetch_title_async(page_url, opts, function(title)
    if title then
      callback(title, "defuddle")
      return
    end

    M.fetch_html_title_async(page_url, opts, function(html_title)
      if html_title then
        callback(html_title, "html")
        return
      end

      callback(url.fallback_title_from_url(page_url), "url")
    end)
  end)
end

return M
