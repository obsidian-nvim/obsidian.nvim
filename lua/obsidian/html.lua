local M = {}

---@param s string|nil
---@return string|nil
M.unescape = function(s)
  if not s then
    return s
  end

  s = s:gsub("&#x(%x+);", function(hex)
    local n = tonumber(hex, 16)
    if not n then
      return ""
    end
    local ok, ch = pcall(vim.fn.nr2char, n)
    return ok and ch or ""
  end)
  s = s:gsub("&#(%d+);", function(dec)
    local n = tonumber(dec, 10)
    if not n then
      return ""
    end
    local ok, ch = pcall(vim.fn.nr2char, n)
    return ok and ch or ""
  end)

  return s:gsub("&amp;", "&")
    :gsub("&lt;", "<")
    :gsub("&gt;", ">")
    :gsub("&quot;", '"')
    :gsub("&apos;", "'")
    :gsub("&#39;", "'")
    :gsub("&nbsp;", " ")
end

---@param title string|nil
---@return string|nil
local function clean_title(title)
  if not title then
    return nil
  end
  title = M.unescape(title:gsub("<[^>]->", " "):gsub("%s+", " "))
  title = vim.trim(title)
  if title ~= "" then
    return title
  end
end

---@param tag string
---@return table<string, string>
local function attrs(tag)
  local out = {}
  for name, _, value in tag:gmatch "([%w_:%-]+)%s*=%s*([\"'])(.-)%2" do
    out[name:lower()] = value
  end
  return out
end

---@param html string|nil
---@return string|nil
M.title_from_html = function(html)
  if not html or html == "" then
    return nil
  end

  for tag in html:gmatch "<%s*[mM][eE][tT][aA][^>]->" do
    local a = attrs(tag)
    local key = (a.property or a.name or ""):lower()
    if (key == "og:title" or key == "twitter:title") and a.content then
      local title = clean_title(a.content)
      if title then
        return title
      end
    end
  end

  local title = html:match "<[tT][iI][tT][lL][eE][^>]*>(.-)</[tT][iI][tT][lL][eE]>"
  return clean_title(title)
end

---@alias obsidian.html.Backend "defuddle"|"pandoc"

---Resolve which conversion backend to use: explicit choice, then config, then auto-detect.
---
---@param backend obsidian.html.Backend|?
---@return obsidian.html.Backend|? backend
---@return string|? err
M.resolve_backend = function(backend)
  if not backend then
    -- pcall: the Obsidian global is only available after setup
    local ok, configured = pcall(function()
      return Obsidian.opts.html.backend
    end)
    backend = ok and configured or nil
  end

  if backend then
    if backend ~= "defuddle" and backend ~= "pandoc" then
      return nil, ("unknown html backend '%s'"):format(backend)
    end
    return backend
  end

  if require("obsidian.defuddle").has_cli() then
    return "defuddle"
  elseif require("obsidian.pandoc").available() then
    return "pandoc"
  end

  return nil, "no html backend available, install the `defuddle` CLI (npm install -g defuddle) or `pandoc`"
end

---Strip markdown images with `data:` URI sources, e.g. decorative UI icons
---that websites inline as base64 svgs. They carry no content and most
---previewers refuse to render data URIs anyway.
---
---@param markdown string
---@return string
M.strip_data_uri_images = function(markdown)
  markdown = markdown:gsub("!%[[^%]]*%]%(data:[^%)]*%)", "")
  -- collapse blank lines left behind by removed images
  markdown = markdown:gsub("\n\n\n+", "\n\n")
  return markdown
end

---@param markdown string
---@return string
local function clean_markdown(markdown)
  return vim.trim(M.strip_data_uri_images(markdown))
end

---@class obsidian.html.ConvertOpts
---@field backend obsidian.html.Backend|? defaults to `Obsidian.opts.html.backend`, else auto-detect (defuddle > pandoc)
---@field mode "page"|"fragment"|? defaults to "fragment"
---@field url string|? source url, included in page-mode frontmatter

---Convert a string of HTML to markdown.
---
---In "fragment" mode the result is bare markdown (no YAML header), suitable
---for pasting into an existing note. In "page" mode the result is prefixed
---with a YAML frontmatter header (title, source, ...), suitable for creating
---a note from a full webpage.
---
---@param html string
---@param opts obsidian.html.ConvertOpts|?
---@param callback fun(markdown: string?, err: string?)
---@return any job
M.to_markdown_async = function(html, opts, callback)
  opts = opts or {}
  local mode = opts.mode or "fragment"

  local backend, err = M.resolve_backend(opts.backend)
  if not backend then
    callback(nil, err)
    return
  end

  if backend == "defuddle" then
    local defuddle = require "obsidian.defuddle"
    return defuddle.convert_async(html, { json = mode == "page" }, function(result, convert_err)
      if not result then
        callback(nil, convert_err)
        return
      end

      if mode ~= "page" then
        callback(clean_markdown(result.markdown), nil)
        return
      end

      local metadata = result.metadata or {}
      if opts.url then
        metadata.source = opts.url
      end
      local header = require("obsidian.webpage").frontmatter(metadata)
      callback(header .. "\n\n" .. clean_markdown(result.markdown), nil)
    end)
  end

  local pandoc = require "obsidian.pandoc"
  return pandoc.convert_async(html, function(markdown, convert_err)
    if not markdown then
      callback(nil, convert_err)
      return
    end

    if mode ~= "page" then
      callback(clean_markdown(markdown), nil)
      return
    end

    local metadata = {
      title = M.title_from_html(html),
      source = opts.url,
    }
    local header = require("obsidian.webpage").frontmatter(metadata)
    callback(header .. "\n\n" .. clean_markdown(markdown), nil)
  end)
end

return M
