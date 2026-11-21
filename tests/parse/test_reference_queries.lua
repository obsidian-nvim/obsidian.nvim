local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

T["cursor, search and index share document reference eligibility"] = function()
  local path = tostring(child.Obsidian.dir / "refs.md")
  child.fn.writefile({
    "---",
    'related: "[[property]]"',
    "---",
    "",
    "```md",
    "[[fenced]]",
    "```",
    "",
    "    [[indented]]",
    "",
    "<!--",
    "[[html_comment]]",
    "-->",
    "",
    "%%",
    "[[obsidian_comment]]",
    "%%",
    "",
    "<!-- html block",
    "--> [[still_in_html_block]]",
    "plain",
    "",
    "`[[inline_code]]`",
    "[[crosses<!-- comment -->comment]]",
    "é [[target\\|label]]",
    "é ![[image.png]]",
    "<https://example.com>",
    "[^footnote]",
    "[[repeat]]",
    "[[repeat]]",
  }, path)
  child.cmd("edit " .. vim.fn.fnameescape(path))

  local result = child.lua [[
    local api = require "obsidian.api"
    local search = require "obsidian.search"
    local cache_note = require "obsidian.cache.note"
    local note = assert(api.current_note())
    local path = tostring(note.path)
    local bufnr = vim.api.nvim_get_current_buf()
    local cursor = {}
    for lnum, line in ipairs(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)) do
      local col = line:find("[", 1, true) or line:find("<https", 1, true)
      if col then
        local _, _, _, ref = api.cursor_link(bufnr, { line = lnum - 1, character = col - 1 })
        if ref then
          cursor[#cursor + 1] = { lnum, ref.range.start_col, ref.raw }
        end
      end
    end
    local links = vim.tbl_map(function(link)
      return { link.line, link.start, link.link }
    end, search.find_links(note))
    local indexed = vim.tbl_map(function(link)
      return { link.line, link.col, link.raw }
    end, assert(cache_note.build(path, tostring(Obsidian.dir))).links_out)
    return { cursor = cursor, links = links, indexed = indexed }
  ]]

  -- Consumers still own projections: search strips the embed marker and
  -- deduplicates; the index stores wiki/Markdown refs, not footnotes/autolinks.
  eq({
    { 2, 10, "[[property]]" },
    { 25, 3, "[[target\\|label]]" },
    { 26, 3, "![[image.png]]" },
    { 27, 0, "<https://example.com>" },
    { 28, 0, "[^footnote]" },
    { 29, 0, "[[repeat]]" },
    { 30, 0, "[[repeat]]" },
  }, result.cursor)
  eq({
    { 2, 10, "[[property]]" },
    { 25, 3, "[[target\\|label]]" },
    { 26, 4, "[[image.png]]" },
    { 27, 0, "<https://example.com>" },
    { 28, 0, "[^footnote]" },
    { 29, 0, "[[repeat]]" },
  }, result.links)
  eq({
    { 2, 11, "[[property]]" },
    { 25, 4, "[[target\\|label]]" },
    { 26, 4, "![[image.png]]" },
    { 29, 1, "[[repeat]]" },
    { 30, 1, "[[repeat]]" },
  }, result.indexed)

  -- Changing only the surrounding syntax in an unsaved buffer exposes the
  -- same reference to cursor lookup without changing the on-disk index.
  eq(
    { "[[fenced]]", "[[property]]" },
    child.lua [[
    vim.api.nvim_buf_set_lines(0, 4, 5, false, { "plain" })
    vim.api.nvim_buf_set_lines(0, 6, 7, false, { "plain" })
    local api = require "obsidian.api"
    local ref = api.cursor_link(0, { line = 5, character = 2 })
    local path = vim.api.nvim_buf_get_name(0)
    local row = assert(require("obsidian.cache.note").build(path, tostring(Obsidian.dir)))
    assert(#row.links_out == 5)
    return { ref, row.links_out[1].raw }
  ]]
  )
end

return T
