local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function open_note(contents)
  local files = h.mock_vault_contents(child.Obsidian.dir, { ["note.md"] = contents })
  child.cmd("edit " .. vim.fn.fnameescape(files["note.md"]))
  child.lua [[vim.b.obsidian_buffer = true]]
end

local function copy(opts)
  opts = vim.tbl_extend("force", { register = "l" }, opts or {})
  return child.lua(([[
    local link = require("obsidian.actions").copy_link(%s)
    return { link, vim.fn.getreg("l") }
  ]]):format(vim.inspect(opts)))
end

T["copies a heading link"] = function()
  open_note "# Heading\nBody"
  child.api.nvim_win_set_cursor(0, { 1, 2 })

  eq({ "[[note#heading]]", "[[note#heading]]" }, copy())
  eq({ "# Heading", "Body" }, child.api.nvim_buf_get_lines(0, 0, -1, false))
end

T["reuses an existing paragraph block"] = function()
  open_note "Body ^existing"
  child.api.nvim_win_set_cursor(0, { 1, 2 })

  eq({ "[[note#^existing]]", "[[note#^existing]]" }, copy())
  eq("Body ^existing", child.api.nvim_get_current_line())
end

T["adds a block ID to an unaddressable paragraph"] = function()
  open_note "First line\nsecond line"
  child.api.nvim_win_set_cursor(0, { 1, 2 })

  local result = copy()
  local line = child.api.nvim_buf_get_lines(0, 1, 2, false)[1]
  local id = line:match "second line (%^[a-z0-9]+)$"
  assert(id, "block ID should be appended to paragraph end")
  eq("[[note#" .. id .. "]]", result[1])
  eq(result[1], result[2])
end

T["falls back to the note on a blank line"] = function()
  open_note "# Heading\n\nBody"
  child.api.nvim_win_set_cursor(0, { 2, 0 })

  eq({ "[[note]]", "[[note]]" }, copy())
  eq("", child.api.nvim_get_current_line())
end

T["respects markdown link style"] = function()
  open_note "# Heading"
  child.api.nvim_win_set_cursor(0, { 1, 2 })
  child.lua [[Obsidian.opts.link.style = "markdown"]]

  eq({ "[note ❯ Heading](note.md#heading)", "[note ❯ Heading](note.md#heading)" }, copy())
end

return T
