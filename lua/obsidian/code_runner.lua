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

local builtin_runners = {
  lua = run_lua,
  vim = run_vim,
  vimscript = run_vim,
  viml = run_vim,
}

---@alias obsidian.code_runner.Runner fun(bufnr: integer, code: string, context: obsidian.code_runner.Context): { cmd: string[] }

---@class obsidian.code_runner.Context
---@field filetype string Language tag from the fenced code block.
---@field block obsidian.parse.document.Region Parsed fenced code block region.
---@field range obsidian.Range Range of the full code block, including its fences.
---@field document obsidian.parse.Document Parsed Markdown document snapshot.

---@type table<string, obsidian.code_runner.Runner>
local runners = {}

--- Register a command to run fenced code blocks with the given language tag.
--- The returned command receives the code on stdin; argv is passed directly to Neovim (no shell).
---@param filetype string
---@param runner obsidian.code_runner.Runner
M.add = function(filetype, runner)
  assert(type(filetype) == "string" and filetype ~= "", "filetype must be a nonempty string")
  assert(type(runner) == "function", "runner must be a function")
  runners[filetype:lower()] = runner
end

M.run = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local cursor = vim.api.nvim_win_get_cursor(0)
  local document = BufferDocument.get(bufnr)
  local cursor_context = document:context_at(Pos.new(cursor[1] - 1, cursor[2]))
  local block = cursor_context.code_block
  if not block or block.kind ~= "fenced_code" or not block.opener_range then
    return
  end

  local opener = assert(document.lines[block.opener_range.start_row + 1], "fence opener is missing")
  local filetype = opener:sub(block.opener_range.end_col + 1):match "^%s*([^%s]+)"
  local custom_runner = filetype and runners[filetype:lower()]
  local builtin_runner = filetype and builtin_runners[filetype:lower()]
  if not custom_runner and not builtin_runner then
    return
  end

  local end_row = block.closer_range and block.closer_range.start_row or block.range.end_row
  local source = {}
  for row = block.opener_range.start_row + 1, end_row - 1 do
    source[#source + 1] = document.lines[row + 1]
  end
  local code = table.concat(source, "\n")

  local ok, err = pcall(function()
    if builtin_runner and not custom_runner then
      builtin_runner(code)
      return
    end

    local registered_runner = assert(custom_runner, "custom runner is missing")
    local runner_context = {
      filetype = assert(filetype, "code block language is missing"),
      block = block,
      range = block.range,
      document = document,
    }
    local result = registered_runner(bufnr, code, runner_context)
    assert(type(result) == "table" and type(result.cmd) == "table", "runner must return { cmd = { ... } }")
    assert(#result.cmd > 0, "runner command must not be empty")

    vim.system(result.cmd, { stdin = code, text = true }, function(command_result)
      local output = command_result.stdout or ""
      local stderr = command_result.stderr or ""
      if command_result.code ~= 0 then
        vim.notify(
          stderr ~= "" and stderr or ("Command exited with code " .. command_result.code),
          vim.log.levels.ERROR
        )
      elseif output ~= "" then
        vim.notify(output)
      end
    end)
  end)
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
