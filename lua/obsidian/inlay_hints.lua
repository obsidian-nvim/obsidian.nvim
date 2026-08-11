local M = {}

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

---@param range lsp.Range
---@param row integer
---@param col integer
---@return boolean
local function range_contains_position_inclusive(range, row, col)
  local starts_before = range.start.line < row or (range.start.line == row and range.start.character <= col)
  local ends_after = range["end"].line > row or (range["end"].line == row and col <= range["end"].character)
  return starts_before and ends_after
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
      matches_cursor = range_contains_position_inclusive(word_range, hint.position.line, hint.position.character)
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
end

---@param client vim.lsp.Client|nil
---@return boolean
local function can_resolve_hint(client)
  if not client then
    return false
  end
  local capabilities = client.server_capabilities or {}
  local provider = capabilities.inlayHintProvider
  return type(provider) == "table" and provider.resolveProvider == true
end

---@param item vim.lsp.inlay_hint.get.ret
---@return boolean
local function is_actionable_obsidian_hint(item)
  local client = vim.lsp.get_client_by_id(item.client_id)
  if not client or client.name ~= "obsidian-ls" then
    return false
  end

  local hint = item.inlay_hint
  return (hint.textEdits ~= nil and #hint.textEdits > 0) or command_from_hint(hint) ~= nil or can_resolve_hint(client)
end

---@param bufnr integer | nil
---@return vim.lsp.inlay_hint.get.ret[]
M.get_actionable_obsidian = function(bufnr)
  return vim.tbl_filter(is_actionable_obsidian_hint, M.get(bufnr))
end

-- TODO: will be unnecessary once something like https://github.com/neovim/neovim/pull/36219 lands in neovim core

---@param bufnr integer
---@param item vim.lsp.inlay_hint.get.ret
---@param hint lsp.InlayHint
local function apply_hint(bufnr, item, hint)
  local client = vim.lsp.get_client_by_id(item.client_id)
  if hint.textEdits and #hint.textEdits > 0 then
    vim.lsp.util.apply_text_edits(hint.textEdits, bufnr, client and client.offset_encoding or "utf-8")
    require("obsidian.ui").update(bufnr)
  end

  local command = command_from_hint(hint)
  if command then
    execute_lsp_command(command)
  end
end

---@param bufnr integer | nil
---@return boolean accepted
M.accept = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local items = M.get(bufnr)
  if vim.tbl_isempty(items) then
    return false
  end

  local item
  for _, current in ipairs(items) do
    if is_actionable_obsidian_hint(current) then
      item = current
      break
    end
  end
  item = item or assert(items[1], "expected at least one inlay hint under the cursor")
  local hint = item.inlay_hint
  local client = vim.lsp.get_client_by_id(item.client_id)
  if client and can_resolve_hint(client) then
    local sent = client:request("inlayHint/resolve", hint, function(err, resolved)
      if err then
        require("obsidian.log").warn("failed to resolve inlay hint: %s", err.message or tostring(err))
      end
      apply_hint(bufnr, item, resolved or hint)
    end, bufnr)
    if sent then
      return true
    end
  end

  apply_hint(bufnr, item, hint)
  return true
end

return M
