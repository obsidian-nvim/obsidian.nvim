local Note = require "obsidian.note"

local M = {
  name = "markdown",
  extensions = { "md", "markdown", "qmd" },
}

---@param path string
---@return string[]
local function read_lines(path)
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if
      vim.api.nvim_buf_is_loaded(bufnr)
      and vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr)) == vim.fs.normalize(path)
    then
      return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    end
  end

  local file, err = io.open(path, "r")
  if file == nil then
    error(err or ("failed to read " .. path))
  end
  local lines = {}
  for line in file:lines() do
    lines[#lines + 1] = line
  end
  file:close()
  return lines
end

---@param lines string[]
---@param start_row integer
---@param end_row integer
---@return string[]
local function slice(lines, start_row, end_row)
  local result = {}
  for index = start_row + 1, math.min(end_row, #lines) do
    result[#result + 1] = lines[index]
  end
  return result
end

---@param ctx obsidian.embed.Context
---@return obsidian.embed.Result
function M.render(ctx)
  local lines = read_lines(ctx.target_path)
  local note = Note.from_lines(lines, ctx.target_path, {
    collect_anchor_links = ctx.ref.anchor ~= nil,
    collect_blocks = ctx.ref.block ~= nil,
    max_lines = math.huge,
  })

  local output
  if ctx.ref.anchor ~= nil then
    local anchor = note:resolve_anchor_link("#" .. ctx.ref.anchor)
    if anchor == nil then
      return {
        lines = {},
        error = 'heading not found: "' .. ctx.ref.anchor .. '"',
        dependencies = { ctx.target_path },
      }
    end
    output = slice(lines, anchor.section.range.start_row, anchor.section.range.end_row)
  elseif ctx.ref.block ~= nil then
    local block = note:resolve_block(ctx.ref.block)
    if block == nil or block.section == nil then
      return {
        lines = {},
        error = 'block not found: "^' .. ctx.ref.block .. '"',
        dependencies = { ctx.target_path },
      }
    end
    output = slice(lines, block.section.range.start_row, block.section.range.end_row)
  else
    output = slice(lines, note.frontmatter_end_line or 0, #lines)
  end

  return {
    lines = output,
    dependencies = { ctx.target_path },
  }
end

return M
