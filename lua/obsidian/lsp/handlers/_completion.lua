local find, sub, lower = string.find, string.sub, string.lower

local CmpType = {
  ref = 1,
  tag = 2,
  -- heading = 3,
  -- heading_all = 4,
  -- block = 5,
  -- block_all = 6,
}

local RefPatterns = {
  [CmpType.ref] = "[[",
  [CmpType.tag] = "#",
  -- [CmpType.heading] = "[[# ",
  -- [CmpType.heading_all] = "[[## ",
  -- [CmpType.block] = "[[^ ",
  -- [CmpType.block_all] = "[[^^ ",
}

---Backtrack through a string to find the first occurrence of '[['.
---
---@param input string
---@return string|? input
---@return string|? search
local find_search_start = function(input)
  for i = string.len(input), 1, -1 do
    local substr = string.sub(input, i)
    if vim.startswith(substr, "]") or vim.endswith(substr, "]") then
      return nil
    elseif vim.startswith(substr, "[[") then
      return substr, string.sub(substr, 3)
      -- elseif vim.startswith(substr, "[") and string.sub(input, i - 1, i - 1) ~= "[" then
      --   return substr, string.sub(substr, 2)
    end
  end
  return nil
end

---Safe version of vim.str_utfindex
---@param text string
---@param vimindex integer|nil
---@return integer
local to_utfindex = function(text, vimindex)
  vimindex = vimindex or #text + 1
  if vim.fn.has "nvim-0.11" == 1 then
    return vim.str_utfindex(text, "utf-8", math.max(0, math.min(vimindex - 1, #text)))
  end
  ---@diagnostic disable-next-line: param-type-mismatch
  return vim.str_utfindex(text, math.max(0, math.min(vimindex - 1, #text)))
end

---@param line_text string
---@return integer? cmp_type
---@return string? prefix
---@return integer? st_character 0-indexed
local function get_cmp_type(line_text, col)
  local cursor_before_line = line_text:sub(1, col - 1)
  local input, search = find_search_start(line_text)

  local cursor_char = to_utfindex(line_text, col)

  local ref_start = cursor_char - vim.fn.strchars(input)

  return 1, search, ref_start

  -- print(input, search)

  -- for t, pattern in vim.spairs(RefPatterns) do -- spairs make sure ref is first
  --   local st, ed = find(line_text, pattern, 1, true)
  --   local st_character = to_utfindex(line_text, st) - 1
  --
  --   if st and ed then
  --     local prefix = sub(line_text, ed + 1)
  --     if vim.fn.strchars(prefix) >= Obsidian.opts.completion.min_chars then -- TODO: unicode
  --       return t, prefix, st_character
  --     end
  --   end
  -- end
end

return {
  get_cmp_type = get_cmp_type,
}
