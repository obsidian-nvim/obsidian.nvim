local BufferDocument = require "obsidian.document"
local Pos = require "obsidian.pos"

local M = {}

local function run_lua(source)
  local chunk, err = loadstring(source, "obsidian-code-block")
  if not chunk then
    error(err, 0)
  end
  chunk()
end

local function run_vim(source)
  vim.cmd(source)
end

local runners = {
  lua = run_lua,
  vim = run_vim,
  vimscript = run_vim,
  viml = run_vim,
}

M.run = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local document = BufferDocument.get(bufnr)
  local context = document:context_at(Pos.new(cursor[1] - 1, cursor[2]))
  local block = context.code_block
  if not block or block.kind ~= "fenced_code" or not block.opener_range then
    return
  end

  local opener = assert(document.lines[block.opener_range.start_row + 1], "fence opener is missing")
  local language = opener:sub(block.opener_range.end_col + 1):match "^%s*([^%s]+)"
  local runner = language and runners[language:lower()]
  if not runner then
    return
  end

  local end_row = block.closer_range and block.closer_range.start_row or block.range.end_row
  local source = {}
  for row = block.opener_range.start_row + 1, end_row - 1 do
    source[#source + 1] = document.lines[row + 1]
  end

  local ok, err = pcall(runner, table.concat(source, "\n"))
  if not ok then
    vim.notify(tostring(err), vim.log.levels.ERROR)
  end
end

M.setup = function(bufnr)
  vim.keymap.set("n", "g==", M.run, {
    buffer = bufnr,
    desc = "Run Markdown code block",
  })
end

return M
