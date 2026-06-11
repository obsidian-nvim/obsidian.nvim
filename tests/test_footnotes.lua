local footnotes = require "obsidian.footnotes"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

---@param lines string[]
---@return integer bufnr
local function make_buf(lines)
  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  return bufnr
end

T["parse_definition"] = function()
  local id, text = footnotes.parse_definition "[^1]: the footnote"
  eq("1", id)
  eq("the footnote", text)

  id, text = footnotes.parse_definition "[^long-note]:no space"
  eq("long-note", id)
  eq("no space", text)

  eq(nil, footnotes.parse_definition "claim[^1] not a definition")
  eq(nil, footnotes.parse_definition "[^1] missing colon")
end

T["definitions"] = function()
  local bufnr = make_buf {
    "claim[^1]",
    "",
    "[^1]: first",
    "[^two]: second",
  }
  local defs = footnotes.definitions(bufnr)
  eq(2, #defs)
  eq({ id = "1", lnum = 3, text = "first" }, defs[1])
  eq({ id = "two", lnum = 4, text = "second" }, defs[2])
end

T["find_refs"] = function()
  local bufnr = make_buf {
    "claim[^1] and again[^1]",
    "",
    "[^1]: first",
  }
  local refs = footnotes.find_refs(bufnr, "1")
  eq(3, #refs)
  eq({ lnum = 1, start_col = 5, end_col = 9 }, refs[1])
  eq({ lnum = 1, start_col = 19, end_col = 23 }, refs[2])
  eq({ lnum = 3, start_col = 0, end_col = 4 }, refs[3])
end

T["insert_definition"] = function()
  local bufnr = make_buf { "claim[^1]" }
  footnotes.insert_definition(bufnr, "1", "the footnote")
  eq({ "claim[^1]", "", "[^1]: the footnote" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))

  -- No blank line between consecutive definitions.
  footnotes.insert_definition(bufnr, "2", "another")
  eq({ "claim[^1]", "", "[^1]: the footnote", "[^2]: another" }, vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
end

T["pick uses vim.ui.select with preview"] = function()
  local bufnr = make_buf {
    "claim[^1]",
    "",
    "[^1]: the footnote",
  }
  vim.api.nvim_set_current_buf(bufnr)

  local select_items, select_opts
  ---@diagnostic disable-next-line: duplicate-set-field
  vim.ui.select = function(items, opts, on_choice)
    select_items, select_opts = items, opts
    on_choice(items[1])
  end

  footnotes.pick(bufnr)

  eq(1, #select_items)
  eq("[^1]: the footnote", select_opts.format_item(select_items[1]))

  local preview = select_opts.preview_item(select_items[1])
  eq({ 3, 0 }, preview.pos)
  eq("[^1]: the footnote", vim.api.nvim_buf_get_lines(preview.buf, 2, 3, false)[1])

  -- Selecting jumps to the definition line.
  eq({ 3, 0 }, vim.api.nvim_win_get_cursor(0))
end

return T
