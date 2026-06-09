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

return M
