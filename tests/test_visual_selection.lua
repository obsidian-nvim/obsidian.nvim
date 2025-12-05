local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[M = require"obsidian.api"]],
}

T["get_visual_selection"] = new_set()

-- Helper to simulate visual selection and get result
-- Sets visual marks '< and '> then calls get_visual_selection
local function select_and_get(child_instance, line, start_col, end_col)
  child_instance.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  -- Set visual selection marks (1-indexed, byte positions)
  child_instance.fn.setpos("'<", { 0, 1, start_col, 0 })
  child_instance.fn.setpos("'>", { 0, 1, end_col, 0 })
  return child_instance.lua_get [[M.get_visual_selection()]]
end

T["get_visual_selection"]["should handle ASCII text correctly"] = function()
  local result = select_and_get(child, "Hello World", 1, 5)
  eq("Hello", result.selection)
  eq(1, result.cscol)
  eq(5, result.cecol)
end

T["get_visual_selection"]["should handle Cyrillic text correctly"] = function()
  -- "Привет" = 6 chars, 12 bytes (each Cyrillic char is 2 bytes in UTF-8)
  -- П=D0 9F, р=D1 80, и=D0 B8, в=D0 B2, е=D0 B5, т=D1 82
  local result = select_and_get(child, "Привет мир", 1, 11)
  -- bytes 1-12 = "Привет" (6 chars * 2 bytes each, but end_col 11 is start of last char)
  eq("Привет", result.selection)
end

T["get_visual_selection"]["should handle Chinese text correctly"] = function()
  -- "你好" = 2 chars, 6 bytes (each CJK char is 3 bytes in UTF-8)
  -- 你=E4 BD A0, 好=E5 A5 BD
  local result = select_and_get(child, "你好世界", 1, 4)
  -- bytes 1-6 = "你好" (selecting from byte 1, end at byte 4 which is start of 好)
  eq("你好", result.selection)
end

T["get_visual_selection"]["should handle emoji correctly"] = function()
  -- Most emoji are 4 bytes in UTF-8
  -- 😀 = F0 9F 98 80
  local result = select_and_get(child, "Hi 😀 there", 4, 4)
  eq("😀", result.selection)
end

T["get_visual_selection"]["should handle mixed ASCII and Cyrillic"] = function()
  -- "test Тест" - selecting "Тест"
  -- "test " = 5 bytes, "Тест" starts at byte 6
  -- Т=D0 A2, е=D0 B5, с=D1 81, т=D1 82
  local result = select_and_get(child, "test Тест end", 6, 13)
  -- bytes 6-13 cover "Тест" (4 chars * 2 bytes = 8 bytes, byte 6 to 13)
  eq("Тест", result.selection)
end

T["get_visual_selection"]["should handle selection at end of line"] = function()
  -- Select last word "мир" from "Привет мир"
  -- "Привет " = 6*2 + 1 = 13 bytes, "мир" starts at byte 14
  local result = select_and_get(child, "Привет мир", 14, 19)
  eq("мир", result.selection)
end

T["get_visual_selection"]["should handle single multibyte character"] = function()
  -- Select single Cyrillic char "Я"
  local result = select_and_get(child, "Я", 1, 1)
  eq("Я", result.selection)
end

T["text_edit_utf8"] = new_set()

-- Helper to apply text replacement using the same UTF-8 logic as replace_selection
-- Uses nvim_buf_set_text directly to test the byte offset calculation
local function apply_edit_and_get_line(child_instance, line, start_col, end_col, new_text)
  child_instance.api.nvim_buf_set_lines(0, 0, -1, false, { line })
  child_instance.fn.setpos("'<", { 0, 1, start_col, 0 })
  child_instance.fn.setpos("'>", { 0, 1, end_col, 0 })

  -- Store new_text in a global variable to avoid escaping issues
  child_instance.lua("_G._test_new_text = ...", { new_text })

  -- Use the same UTF-8 byte calculation logic as in api.lua
  child_instance.lua [[
    local viz = M.get_visual_selection()
    local bufnr = vim.api.nvim_get_current_buf()
    local line = vim.api.nvim_buf_get_lines(bufnr, viz.cerow - 1, viz.cerow, false)[1]

    -- Calculate end position using the same logic as get_utf8_char_end
    local end_col = viz.cecol
    if line and viz.cecol <= #line then
      local byte = line:byte(viz.cecol)
      if byte then
        local char_bytes = 1
        if byte >= 240 then char_bytes = 4
        elseif byte >= 224 then char_bytes = 3
        elseif byte >= 192 then char_bytes = 2
        end
        end_col = viz.cecol + char_bytes
      end
    end

    -- Apply replacement using nvim_buf_set_text (same as LSP would do internally)
    local new_lines = vim.split(_G._test_new_text, "\n", { plain = true })
    vim.api.nvim_buf_set_text(
      bufnr,
      viz.csrow - 1,
      viz.cscol - 1,
      viz.cerow - 1,
      end_col - 1,
      new_lines
    )
  ]]

  return child_instance.api.nvim_get_current_line()
end

T["text_edit_utf8"]["should replace Cyrillic text correctly"] = function()
  -- "Привет мир" - replace "Привет" with "[[Привет]]"
  local result = apply_edit_and_get_line(child, "Привет мир", 1, 11, "[[Привет]]")
  eq("[[Привет]] мир", result)
end

T["text_edit_utf8"]["should replace Chinese text correctly"] = function()
  -- "你好世界" - replace "你好" with "[[你好]]"
  local result = apply_edit_and_get_line(child, "你好世界", 1, 4, "[[你好]]")
  eq("[[你好]]世界", result)
end

T["text_edit_utf8"]["should replace emoji correctly"] = function()
  -- "Hello 😀 World" - replace "😀" with ":smile:"
  local result = apply_edit_and_get_line(child, "Hello 😀 World", 7, 7, ":smile:")
  eq("Hello :smile: World", result)
end

T["text_edit_utf8"]["should not corrupt surrounding Cyrillic text"] = function()
  -- "Привет World Мир" - replace "World" with "Земля"
  -- "Привет " = 13 bytes, "World" starts at 14
  local result = apply_edit_and_get_line(child, "Привет World Мир", 14, 18, "Земля")
  eq("Привет Земля Мир", result)
end

T["text_edit_utf8"]["should handle replacement at line end"] = function()
  -- "Hello Мир" - replace "Мир" at end
  -- "Hello " = 6 bytes, "Мир" starts at 7
  local result = apply_edit_and_get_line(child, "Hello Мир", 7, 11, "[[Мир]]")
  eq("Hello [[Мир]]", result)
end

T["text_edit_utf8"]["should handle mixed scripts replacement"] = function()
  -- "test тест test" - replace middle "тест"
  -- "test " = 5 bytes, "тест" starts at byte 6, is 8 bytes (4 chars * 2)
  local result = apply_edit_and_get_line(child, "test тест test", 6, 13, "ТЕСТ")
  eq("test ТЕСТ test", result)
end

return T
