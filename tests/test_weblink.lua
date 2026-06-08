local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local weblink = require "obsidian.weblink"

local T = new_set()

T["title_from_defuddle_markdown"] = function()
  local markdown = [[---
title: "Example Domain"
source: "https://example.com"
---

Body text.]]

  eq("Example Domain", weblink.title_from_defuddle_markdown(markdown))
end

T["title_from_html prefers social metadata"] = function()
  local html = [[
<html><head>
<title>Fallback &amp; Title</title>
<meta content="OG &amp; Title" property="og:title">
</head></html>]]

  eq("OG & Title", weblink.title_from_html(html))
end

T["fallback_title_from_url returns readable slug"] = function()
  eq("My Cool Post", weblink.fallback_title_from_url "https://example.com/blog/my-cool-post.html?utm=1")
  eq("Café", weblink.fallback_title_from_url "https://example.com/caf%C3%A9")
end

T["format_markdown_link escapes label and url"] = function()
  eq("[A \\[title\\]](https://example.com/a\\)b)", weblink.format_markdown_link("https://example.com/a)b", "A [title]"))
end

T["url_at_cursor finds bare remote url"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "See https://example.com/page)." })
  vim.api.nvim_win_set_cursor(0, { 1, 8 })

  local found = assert(weblink.url_at_cursor(buf))
  eq("https://example.com/page", found.url)
  eq(4, found.start_col)
  eq(28, found.end_col)
end

T["url_at_cursor replaces whole markdown link destination"] = function()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "See [old](https://example.com/page) now" })
  vim.api.nvim_win_set_cursor(0, { 1, 12 })

  local found = assert(weblink.url_at_cursor(buf))
  eq("https://example.com/page", found.url)
  eq(4, found.start_col)
  eq(35, found.end_col)
end

return T
