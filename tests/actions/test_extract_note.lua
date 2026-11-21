local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function open_source(lines)
  local files = h.mock_vault_contents(child.Obsidian.dir, {
    ["source.md"] = table.concat(lines, "\n"),
  })
  child.cmd("edit " .. vim.fn.fnameescape(files["source.md"]))
  child.lua [[
    Obsidian.opts.frontmatter.enabled = false
    vim.b.obsidian_buffer = true
  ]]
  return files["source.md"]
end

T["extract_note keeps first line in downward linewise visual mode V"] = function()
  local source_path = open_source { "A", "B", "C" }
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("V", "j")

  child.lua [[require("obsidian.actions").extract_note "Extracted Note"]]

  local source_lines = h.read(source_path)
  eq(2, #source_lines)
  eq(true, source_lines[1]:match "^%[%[.*|Extracted Note%]%]$" ~= nil)
  eq("C", source_lines[2])

  local extracted_lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("A", extracted_lines[#extracted_lines - 1])
  eq("B", extracted_lines[#extracted_lines])
end

T["extract_note keeps first line in upward linewise visual mode V"] = function()
  local source_path = open_source { "A", "B", "C" }
  child.api.nvim_win_set_cursor(0, { 2, 0 })
  child.type_keys("V", "k")

  child.lua [[require("obsidian.actions").extract_note "Upward Note"]]

  local source_lines = h.read(source_path)
  eq(2, #source_lines)
  eq(true, source_lines[1]:match "^%[%[.*|Upward Note%]%]$" ~= nil)
  eq("C", source_lines[2])

  local extracted_lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("A", extracted_lines[#extracted_lines - 1])
  eq("B", extracted_lines[#extracted_lines])
end

T["extract_note handles multibyte UTF-8 and trailing empty line in V mode"] = function()
  local source_path = open_source { "First line", "мир 😀", "" }
  child.api.nvim_win_set_cursor(0, { 1, 0 })
  child.type_keys("V", "2j")

  child.lua [[require("obsidian.actions").extract_note "Utf8 Note"]]

  local source_lines = h.read(source_path)
  eq(1, #source_lines)
  eq(true, source_lines[1]:match "^%[%[.*|Utf8 Note%]%]$" ~= nil)

  local extracted_lines = child.api.nvim_buf_get_lines(0, 0, -1, false)
  eq("First line", extracted_lines[#extracted_lines - 2])
  eq("мир 😀", extracted_lines[#extracted_lines - 1])
  eq("", extracted_lines[#extracted_lines])
end

return T
