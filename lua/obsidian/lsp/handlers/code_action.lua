---@class obsidian.lsp.ctx
---@field buf number - buffer number
---@field win number - window number
---@field row number - current line number
---@field col number - current column number
---@field line string - current line
---@field ts_node TSNode|nil - current TS node
---@field ts_type string|nil - type of the current TS node
---@field ts_range table<number, number, number, number>|nil - range of the current TS node
---@field bufname string - full path to file in buffer
---@field root string - root directory of the file
---@field filetype string - filetype
---@field range Range|nil - range of the current selection

---@param params lsp.CodeActionParams
---@return obsidian.lsp.ctx
local function get_ctx(params)
  if not (params and params.textDocument) then
    return {}
  end

  local buf = vim.uri_to_bufnr(params.textDocument.uri)
  local cursor = vim.api.nvim_win_get_cursor(vim.fn.bufwinid(buf))
  local row = params.range and params.range.start.line or cursor[1]
  local col = params.range and params.range.start.character or cursor[2]
  local node = vim.treesitter.get_node()

  local file = vim.uri_to_fname(params.textDocument.uri)
  local root = vim.fs.root(file, { ".git", ".gitignore" }) or ""

  local ctx = {
    buf = buf,
    win = vim.fn.win_findbuf(buf)[1],
    row = row,
    col = col,
    line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1],
    ts_type = node and node:type() or nil,
    ts_range = node and { node:range() },
    bufname = file,
    root = root,
    filetype = vim.api.nvim_get_option_value("filetype", { buf = buf }),
    range = params.range,
  }
  return ctx
end

local Config = require "obsidian.lsp.config"

local function code_action(ctx)
  local list_of_actions = vim.tbl_values(Config.actions)
  return vim
    .iter(list_of_actions)
    :map(function(action)
      action.ctx = ctx
      return action
    end)
    :totable()
end

---@param params lsp.CodeActionParams
---@param handler function
return function(_, params, handler, _)
  local ctx = get_ctx(params)
  handler(nil, code_action(ctx))
end
