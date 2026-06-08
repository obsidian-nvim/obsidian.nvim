local M = {}

---@class obsidian.weblink.CursorUrl
---@field url string
---@field bufnr integer
---@field lnum integer 1-indexed line number
---@field start_col integer 0-indexed byte offset, inclusive
---@field end_col integer 0-indexed byte offset, exclusive

local function html_unescape(s)
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

local function clean_title(title)
  if not title then
    return nil
  end
  title = html_unescape(title:gsub("<[^>]->", " "):gsub("%s+", " "))
  title = vim.trim(title)
  if title ~= "" then
    return title
  end
end

---@param markdown string|nil
---@return string|nil
M.title_from_defuddle_markdown = function(markdown)
  if not markdown or markdown == "" then
    return nil
  end

  local frontmatter = markdown:match "^%s*%-%-%-%s*\n(.-)\n%-%-%-"
  if frontmatter then
    for line in frontmatter:gmatch "[^\n]+" do
      local title = line:match "^title:%s*(.-)%s*$"
      if title then
        title = vim.trim(title)
        local quoted = title:match '^"(.*)"$' or title:match "^'(.*)'$"
        if quoted then
          title = quoted:gsub('\\"', '"'):gsub("\\'", "'")
        end
        return clean_title(title)
      end
    end
  end

  for line in markdown:gmatch "[^\n]+" do
    local heading = line:match "^#%s+(.+)$"
    if heading then
      return clean_title(heading)
    end
  end
end

---@param html string|nil
---@return string|nil
M.title_from_html = function(html)
  if not html or html == "" then
    return nil
  end

  local function attrs(tag)
    local out = {}
    for name, _, value in tag:gmatch "([%w_:%-]+)%s*=%s*([\"'])(.-)%2" do
      out[name:lower()] = value
    end
    return out
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

local function percent_decode(s)
  local ok, decoded = pcall(vim.uri_decode, s)
  return ok and decoded or s
end

local function title_case_if_slug(s)
  if s:find "%u" then
    return s
  end
  return (s:gsub("(%a)([%w']*)", function(first, rest)
    return first:upper() .. rest
  end))
end

---@param url string
---@return string
M.fallback_title_from_url = function(url)
  local host = url:match "^https?://([^/%?#]+)" or url
  local path = url:match "^https?://[^/%?#]+([^%?#]*)" or ""
  local last

  for segment in path:gmatch "[^/]+" do
    if segment ~= "" then
      last = segment
    end
  end

  if last and last ~= "" then
    last = percent_decode(last:gsub("+", " "))
    last = last:gsub("%.html?$", "")
    last = last:gsub("[-_%.]+", " ")
    last = vim.trim(last:gsub("%s+", " "))
    if last ~= "" then
      return title_case_if_slug(last)
    end
  end

  host = percent_decode(host):gsub("^www%.", "")
  return host ~= "" and host or url
end

---@param cmd string[]
---@return string|nil stdout
---@return string|nil err
local function curl(cmd)
  local ok, out = pcall(function()
    return vim.system(cmd, { text = true }):wait()
  end)
  if not ok then
    return nil, tostring(out)
  end

  if out.code ~= 0 or not out.stdout or out.stdout == "" then
    return nil, ("curl failed (%d): %s"):format(out.code, vim.trim(out.stderr or ""))
  end

  return out.stdout, nil
end

---@param url string
---@param opts { timeout: integer? }|?
---@return string|nil markdown
---@return string|nil err
M.fetch_defuddle_markdown = function(url, opts)
  opts = opts or {}
  return curl { "curl", "-fsSL", "--compressed", "-m", tostring(opts.timeout or 15), "https://defuddle.md/" .. url }
end

---@param url string
---@param opts { timeout: integer? }|?
---@return string|nil title
---@return string|nil err
M.fetch_defuddle_title = function(url, opts)
  local markdown, err = M.fetch_defuddle_markdown(url, opts)
  if not markdown then
    return nil, err
  end

  local title = M.title_from_defuddle_markdown(markdown)
  if not title then
    return nil, "defuddle response did not include a title"
  end

  return title, nil
end

---@param url string
---@param opts { timeout: integer? }|?
---@return string|nil html
---@return string|nil err
M.fetch_html = function(url, opts)
  opts = opts or {}
  return curl { "curl", "-fsSL", "--compressed", "-m", tostring(opts.timeout or 15), url }
end

---@param url string
---@param opts { timeout: integer? }|?
---@return string|nil title
---@return string|nil err
M.fetch_html_title = function(url, opts)
  local html, err = M.fetch_html(url, opts)
  if not html then
    return nil, err
  end

  local title = M.title_from_html(html)
  if not title then
    return nil, "html response did not include a title"
  end

  return title, nil
end

---@param url string
---@param opts { timeout: integer? }|?
---@return string title
---@return "defuddle"|"html"|"url" source
M.title_from_url = function(url, opts)
  local title = M.fetch_defuddle_title(url, opts)
  if title then
    return title, "defuddle"
  end

  title = M.fetch_html_title(url, opts)
  if title then
    return title, "html"
  end

  return M.fallback_title_from_url(url), "url"
end

local function escape_markdown_label(label)
  return label:gsub("\\", "\\\\"):gsub("%]", "\\]"):gsub("%[", "\\[")
end

local function escape_markdown_url(url)
  return url:gsub("\\", "\\\\"):gsub("%)", "\\)")
end

---@param url string
---@param title string
---@return string
M.format_markdown_link = function(url, title)
  return ("[%s](%s)"):format(escape_markdown_label(title), escape_markdown_url(url))
end

local function trim_url(raw)
  local url = raw:gsub("[>%]%}%.,;:!?]+$", "")
  while url:sub(-1) == ")" do
    local opens = select(2, url:gsub("%(", ""))
    local closes = select(2, url:gsub("%)", ""))
    if closes <= opens then
      break
    end
    url = url:sub(1, -2)
  end
  return url
end

---@param bufnr integer?
---@return obsidian.weblink.CursorUrl|nil
M.url_at_cursor = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lnum, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  local line = vim.api.nvim_buf_get_lines(bufnr, lnum - 1, lnum, false)[1]
  if not line then
    return nil
  end

  for link_start, url_start, url, url_end, link_end in line:gmatch "()%[[^%]]-%]%(()(https?://[^%s%)]+)()%)()" do
    if cursor_col >= url_start - 1 and cursor_col < url_end - 1 then
      return {
        url = url,
        bufnr = bufnr,
        lnum = lnum,
        start_col = link_start - 1,
        end_col = link_end - 1,
      }
    end
  end

  for start_pos, raw, raw_end in line:gmatch "()(https?://[^%s<>'\"]+)()" do
    local url = trim_url(raw)
    local end_col = start_pos - 1 + #url
    if cursor_col >= start_pos - 1 and cursor_col < end_col then
      return {
        url = url,
        bufnr = bufnr,
        lnum = lnum,
        start_col = start_pos - 1,
        end_col = end_col,
      }
    end
    if raw_end <= start_pos then
      break
    end
  end
end

return M
