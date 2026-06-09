local M = {}

---@class obsidian.url.CursorUrl
---@field url string
---@field bufnr integer
---@field lnum integer 1-indexed line number
---@field start_col integer 0-indexed byte offset, inclusive
---@field end_col integer 0-indexed byte offset, exclusive
---@field text string original buffer text covered by the range

---@param s string
---@return string
local function percent_decode(s)
  local ok, decoded = pcall(vim.uri_decode, s)
  return ok and decoded or s
end

---@param s string
---@return string
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

---@param raw string
---@return string
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

---@param bufnr integer
---@param lnum integer 1-indexed line number
---@param cursor_col integer 0-indexed byte offset
---@return obsidian.url.CursorUrl|nil
M.at_pos = function(bufnr, lnum, cursor_col)
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
        text = line:sub(link_start, link_end - 1),
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
        text = line:sub(start_pos, end_col),
      }
    end
    if raw_end <= start_pos then
      break
    end
  end
end

-- NOTE: can not use vim.ui._get_urls since that uses treesitter, and bare urls don't work
---@param bufnr integer?
---@return obsidian.url.CursorUrl|nil
M.at_cursor = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local lnum, cursor_col = unpack(vim.api.nvim_win_get_cursor(0))
  return M.at_pos(bufnr, lnum, cursor_col)
end

return M
