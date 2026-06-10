local M = {}

local defuddle = require "obsidian.defuddle"
local html = require "obsidian.html"
local url = require "obsidian.url"
local webpage = require "obsidian.webpage"

---@class obsidian.weblink.CursorUrl : obsidian.url.CursorUrl

M.note_from_defuddle_markdown = defuddle.note_from_markdown
M.title_from_defuddle_markdown = defuddle.title_from_markdown
M.title_from_html = html.title_from_html
M.fallback_title_from_url = url.fallback_title_from_url
M.url_at_cursor = url.at_cursor
M.url_at_pos = url.at_pos

M.fetch_defuddle_markdown_async = defuddle.fetch_markdown_async
M.fetch_defuddle_title_async = defuddle.fetch_title_async
M.fetch_html_async = webpage.fetch_html_async
M.fetch_html_title_async = webpage.fetch_html_title_async
M.title_from_url_async = webpage.title_from_url_async

M.html_to_markdown_async = html.to_markdown_async
M.resolve_html_backend = html.resolve_backend
M.frontmatter_from_metadata = webpage.frontmatter
M.note_from_html_async = webpage.note_from_html_async

local function escape_markdown_label(label)
  return label:gsub("\\", "\\\\"):gsub("%]", "\\]"):gsub("%[", "\\[")
end

local function escape_markdown_url(url_text)
  return url_text:gsub("\\", "\\\\"):gsub("%)", "\\)")
end

---@param url_text string
---@param title string
---@return string
M.format_markdown_link = function(url_text, title)
  return ("[%s](%s)"):format(escape_markdown_label(title), escape_markdown_url(url_text))
end

return M
