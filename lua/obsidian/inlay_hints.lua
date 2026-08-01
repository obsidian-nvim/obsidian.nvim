local M = {}

---@class obsidian.InlayHintContext
---@field bufnr     integer
---@field row       integer                                          0-based row being scanned.
---@field line      string                                           Line text.
---@field lsp_range lsp.Range | nil                                  Requested LSP range.
---@field add       fun(spec: lsp.InlayHint): lsp.InlayHint Add a hint for the current line.

---@class obsidian.InlayHintProvider
---@field name string
---@field scan  fun(ctx: obsidian.InlayHintContext): lsp.InlayHint[] | nil Called once for each scanned line.

---@class obsidian.InlayHintEntry
---@field bufnr       integer
---@field range       obsidian.Range
---@field hint        lsp.InlayHint

---@type obsidian.InlayHintProvider[]
local providers = {}

local next_provider_id = 0

local function line_in_range(range, line_nr)
  if not range then
    return true
  end
  return range.start.line <= line_nr and line_nr <= range["end"].line
end

local function is_lsp_range(range)
  return type(range) == "table" and range.start ~= nil and range["end"] ~= nil
end

local function current_word_range(bufnr, row, col)
  local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
  if not line then
    return nil
  end

  return vim.api.nvim_buf_call(bufnr, function()
    local offset = 0
    while offset <= #line do
      local _, start_col, end_col = unpack(vim.fn.matchstrpos(line, [[\k\+]], offset))
      if start_col == -1 or start_col > col then
        return nil
      elseif start_col <= col and col < end_col then
        return { start = { line = row, character = start_col }, ["end"] = { line = row, character = end_col } }
      end
      offset = end_col
    end
  end)
end

---@param range lsp.Range
---@param row   integer
---@param col   integer
---@return boolean
local function range_contains_position(range, row, col)
  local starts_before = range.start.line < row or (range.start.line == row and range.start.character <= col)
  local ends_after = range["end"].line > row or (range["end"].line == row and col < range["end"].character)
  return starts_before and ends_after
end

---@param provider obsidian.InlayHintProvider
M.register = function(provider)
  vim.validate("provider", provider, "table")
  vim.validate("provider.scan", provider.scan, "function")
  vim.validate("provider.name", provider.name, "string")
  providers[#providers + 1] = provider
end

---@param name string
M.unregister = function(name)
  for i = #providers, 1, -1 do
    if providers[i].name == name then
      table.remove(providers, i)
    end
  end
end

---@param bufnr integer
---@param range lsp.Range | nil
---@return lsp.InlayHint[]
M.collect = function(bufnr, range)
  bufnr = bufnr or 0

  ---@type lsp.InlayHint[]
  local hints = {}

  -- Built-in link suggestions.
  for _, hint in ipairs(require "obsidian.lsp.inlay_hints.link"(bufnr, range)) do
    hints[#hints + 1] = hint
  end

  if #providers > 0 then
    local line_count = vim.api.nvim_buf_line_count(bufnr)
    local start_row = range and range.start.line or 0
    local end_row = range and range["end"].line or (line_count - 1)
    start_row = math.max(0, start_row)
    end_row = math.min(line_count - 1, end_row)

    for row = start_row, end_row do
      if line_in_range(range, row) then
        local line = vim.api.nvim_buf_get_lines(bufnr, row, row + 1, false)[1]
        if line then
          for _, provider in ipairs(providers) do
            local function add(hint)
              -- local hint = spec_to_hint(bufnr, spec, row)
              hints[#hints + 1] = hint
              return hint
            end

            local ok, result = pcall(provider.scan, {
              bufnr = bufnr,
              row = row,
              line = line,
              lsp_range = range,
              add = add,
            })
            if ok then
              for _, spec in ipairs(result or {}) do
                add(spec)
              end
            else
              require("obsidian.log").warn("inlay hint provider '%s' failed: %s", provider.name, result)
            end
          end
        end
      end
    end
  end

  return hints
end

---@param bufnr integer | nil
---@return vim.lsp.inlay_hint.get.ret[]
M.get = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  if not vim.lsp.inlay_hint or type(vim.lsp.inlay_hint.get) ~= "function" then
    return {}
  end

  local row, col = unpack(vim.api.nvim_win_get_cursor(0))
  row = row - 1
  ---@cast row integer
  ---@cast col integer
  local word_range = current_word_range(bufnr, row, col)
  local matches = {}

  for _, item in ipairs(vim.lsp.inlay_hint.get { bufnr = bufnr }) do
    local hint = item.inlay_hint
    local data_range = type(hint.data) == "table" and hint.data.range or nil
    local matches_cursor
    if is_lsp_range(data_range) then
      ---@cast data_range lsp.Range
      matches_cursor = range_contains_position(data_range, row, col)
    elseif word_range then
      matches_cursor = range_contains_position(word_range, hint.position.line, hint.position.character)
    end

    if matches_cursor then
      matches[#matches + 1] = item
    end
  end

  return matches
end

---@param hint lsp.InlayHint
---@return lsp.Command | nil
local function command_from_hint(hint)
  local hint_table = hint --[[@as table]]
  if hint_table.command then
    return hint_table.command
  elseif type(hint.label) == "table" then
    for _, part in ipairs(hint.label) do
      if type(part) == "table" and part.command then
        return part.command
      end
    end
  end
end

---@param command lsp.Command
local function execute_lsp_command(command)
  local handler = vim.lsp.commands[command.command]
  if handler then
    return handler(command, {})
  end

  -- Fall back to the LSP client. This is useful for commands implemented by
  -- another client and keeps the stored command table LSP-shaped.
  ---@diagnostic disable-next-line: undefined-field
  return vim.lsp.buf.execute_command(command)
end

-- TODO: will be unnecessary once something like https://github.com/neovim/neovim/pull/36219 lands in neovim core

---@param bufnr integer | nil
---@return boolean accepted
M.accept = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local items = M.get(bufnr)
  if vim.tbl_isempty(items) then
    return false
  end

  local item = assert(items[1], "expected at least one inlay hint under the cursor")
  local hint = item.inlay_hint
  if hint.textEdits and #hint.textEdits > 0 then
    local client = vim.lsp.get_client_by_id(item.client_id)
    vim.lsp.util.apply_text_edits(hint.textEdits, bufnr, client and client.offset_encoding or "utf-8")
    require("obsidian.ui").update(bufnr)
  end

  local command = command_from_hint(hint)
  if command then
    execute_lsp_command(command)
  end

  return true
end

return M
