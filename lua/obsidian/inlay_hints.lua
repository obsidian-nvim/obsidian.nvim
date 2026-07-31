local Range = require "obsidian.range"

local M = {}

---@alias obsidian.InlayHintCommandSpec lsp.Command|fun(entry: obsidian.InlayHintEntry, ...: any)

---@class obsidian.InlayHintSpec
---@field position? lsp.Position|integer Position for the rendered hint. An integer is treated as the column on the current line.
---@field range? obsidian.Range|lsp.Range Range that should trigger this hint's action when the cursor is inside it.
---@field hinted_range? obsidian.Range|lsp.Range Deprecated alias for `range`.
---@field label string|lsp.InlayHintLabelPart[]
---@field kind? lsp.InlayHintKind|integer
---@field textEdits? lsp.TextEdit[]
---@field text_edits? lsp.TextEdit[] Alias for `textEdits`.
---@field tooltip? string|lsp.MarkupContent
---@field paddingLeft? boolean
---@field paddingRight? boolean
---@field padding_left? boolean Alias for `paddingLeft`.
---@field padding_right? boolean Alias for `paddingRight`.
---@field data? any
---@field command? obsidian.InlayHintCommandSpec Command to execute for this hint. Function commands are stored internally and exposed as an LSP command.
---@field command_title? string

---@class obsidian.InlayHintContext
---@field bufnr integer
---@field row integer 0-based row being scanned.
---@field line string Line text.
---@field lsp_range lsp.Range|nil Requested LSP range.
---@field add fun(spec: obsidian.InlayHintSpec): lsp.InlayHint Add a hint for the current line.

---@class obsidian.InlayHintProvider
---@field name? string
---@field scan fun(ctx: obsidian.InlayHintContext): obsidian.InlayHintSpec[]|nil Called once for each scanned line.

---@class obsidian.InlayHintEntry
---@field bufnr integer
---@field range obsidian.Range
---@field hint lsp.InlayHint
---@field command? lsp.Command
---@field command_id? integer

---@type obsidian.InlayHintProvider[]
local providers = {}

---@type table<integer, { bufnr: integer, command: fun(...) }>
local function_commands = {}
local next_command_id = 0
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

---@param range obsidian.Range|lsp.Range|nil
---@return obsidian.Range|nil
local function normalize_range(range)
  if not range then
    return nil
  elseif is_lsp_range(range) then
    ---@cast range lsp.Range
    return Range.lsp(range)
  else
    ---@cast range obsidian.Range
    return range
  end
end

---@param bufnr integer
---@param spec obsidian.InlayHintSpec
---@param row integer
---@return lsp.InlayHint
---@return obsidian.InlayHintEntry
local function spec_to_hint(bufnr, spec, row)
  local hint_range = normalize_range(spec.range or spec.hinted_range)

  local position = spec.position
  if type(position) == "number" then
    position = { line = row, character = position }
  elseif not position then
    if hint_range then
      position = { line = hint_range.end_row, character = hint_range.end_col }
    else
      position = { line = row, character = 0 }
    end
  end

  local command = spec.command
  local command_id
  ---@type lsp.Command|nil
  local lsp_command
  ---@type fun(entry: obsidian.InlayHintEntry, ...: any)|nil
  local command_fn
  if type(command) == "function" then
    command_fn = command
    ---@cast command_fn fun(entry: obsidian.InlayHintEntry, ...: any)
    next_command_id = next_command_id + 1
    command_id = next_command_id
    lsp_command = {
      title = spec.command_title or "Obsidian inlay hint",
      command = "obsidian.inlay_hint_command",
      arguments = { command_id },
    }
  elseif type(command) == "table" then
    lsp_command = command
  end

  local label = spec.label
  if lsp_command then
    if type(label) == "string" then
      label = { { value = label, command = lsp_command } }
    elseif type(label) == "table" and #label > 0 then
      local has_command = false
      for _, part in ipairs(label) do
        if type(part) == "table" and part.command then
          has_command = true
          break
        end
      end
      if not has_command then
        if type(label[#label]) == "table" then
          label[#label].command = lsp_command
        else
          label[#label] = { value = tostring(label[#label]), command = lsp_command }
        end
      end
    end
  end

  ---@type lsp.InlayHint|table
  local hint = {
    position = position,
    label = label,
    kind = spec.kind,
    textEdits = spec.textEdits or spec.text_edits,
    tooltip = spec.tooltip,
    paddingLeft = spec.paddingLeft,
    paddingRight = spec.paddingRight,
    data = spec.data,
  }

  if hint.paddingLeft == nil then
    hint.paddingLeft = spec.padding_left
  end
  if hint.paddingRight == nil then
    hint.paddingRight = spec.padding_right
  end

  if not hint_range then
    if hint.textEdits and hint.textEdits[1] and hint.textEdits[1].range then
      hint_range = Range.lsp(hint.textEdits[1].range)
    else
      hint_range = Range.new(position.line, position.character, position.line, position.character)
    end
  end

  ---@type obsidian.InlayHintEntry
  local entry = {
    bufnr = bufnr,
    range = hint_range,
    hint = hint,
    command = lsp_command,
    command_id = command_id,
  }

  if command_id and command_fn then
    function_commands[command_id] = {
      bufnr = bufnr,
      command = function(...)
        return command_fn(entry, ...)
      end,
    }
  end

  return hint, entry
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
        return {
          start = { line = row, character = start_col },
          ["end"] = { line = row, character = end_col },
        }
      end
      offset = end_col
    end
  end)
end

---@param provider obsidian.InlayHintProvider|fun(ctx: obsidian.InlayHintContext): obsidian.InlayHintSpec[]|nil
---@return fun() unregister
M.register = function(provider)
  if type(provider) == "function" then
    provider = { scan = provider }
  end
  assert(type(provider) == "table", "inlay hint provider must be a function or table")
  assert(type(provider.scan) == "function", "inlay hint provider requires a scan(ctx) function")

  next_provider_id = next_provider_id + 1
  provider.name = provider.name or ("custom." .. next_provider_id)
  providers[#providers + 1] = provider

  return function()
    M.unregister(provider.name)
  end
end

---@param name string
M.unregister = function(name)
  for i = #providers, 1, -1 do
    if providers[i].name == name then
      table.remove(providers, i)
    end
  end
  M.clear()
end

---@param bufnr integer|nil
M.clear = function(bufnr)
  for id, command in pairs(function_commands) do
    if not bufnr or command.bufnr == bufnr then
      function_commands[id] = nil
    end
  end
end

---@param bufnr integer
---@param range lsp.Range|nil
---@return lsp.InlayHint[]
M.collect = function(bufnr, range)
  bufnr = bufnr or 0
  M.clear(bufnr)

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
            local function add(spec)
              local hint = spec_to_hint(bufnr, spec, row)
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

---@param bufnr integer|nil
---@return vim.lsp.inlay_hint.get.ret[]
M.get = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local row, col = unpack(vim.api.nvim_win_get_cursor(0))

  local range = current_word_range(bufnr, row - 1, col)
  if not range then
    return {}
  end

  return vim.lsp.inlay_hint.get { bufnr = bufnr, range = range }
end

---@param id integer
M.execute_command = function(id, ...)
  local registered = function_commands[id]
  if not registered then
    require("obsidian.log").warn("inlay hint command not found: %s", tostring(id))
    return
  end

  local ok, err = pcall(registered.command, ...)
  if not ok then
    require("obsidian.log").err("inlay hint command failed: %s", err)
  end
end

---@param hint lsp.InlayHint
---@return lsp.Command|nil
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
  if command.command == "obsidian.inlay_hint_command" then
    local args = command.arguments or {}
    ---@cast args any[]
    if args[1] then
      return M.execute_command(args[1] --[[@as integer]], unpack(args, 2))
    end
    return
  end

  local handler = vim.lsp.commands[command.command]
  if handler then
    return handler(command, {})
  end

  -- Fall back to the LSP client. This is useful for commands implemented by
  -- another client and keeps the stored command table LSP-shaped.
  ---@diagnostic disable-next-line: undefined-field
  return vim.lsp.buf.execute_command(command)
end

-- TODO: will be unnecessary once something like https://github.com/neovim/neovim/pull/36219 lands

---@param bufnr integer|nil
---@return boolean accepted
M.accept = function(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local items = M.get(bufnr)
  if vim.tbl_isempty(items) then
    return false
  end

  local item = assert(items[1])
  local hint = item.inlay_hint
  vim.print(hint)
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
