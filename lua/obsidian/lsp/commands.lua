--- Command IDs deliberately exposed to LSP clients, independent of the Lua actions interface.
local M = {}

---@class obsidian.lsp.CommandHandler
---@field run function
---@field client fun(command: lsp.Command)

---@param fn function
---@return obsidian.lsp.CommandHandler
local function handler(fn)
  return {
    run = fn,
    client = vim.schedule_wrap(function(command)
      fn(unpack(command.arguments or {}))
    end),
  }
end

---@type table<string, obsidian.lsp.CommandHandler>
local builtins = {}
---@type table<string, obsidian.lsp.CommandHandler>
local custom = {}

---@param name string
---@param fn function
local function add_builtin(name, fn)
  builtins["obsidian." .. name] = handler(fn)
end

-- Code actions delegate to the scriptable workflows.
for _, name in ipairs {
  "add_attachment",
  "add_bookmark",
  "add_property",
  "add_tag",
  "backlink_suggestions",
  "delete_note",
  "extract_note",
  "insert_link",
  "insert_tag",
  "insert_template",
  "link",
  "link_new",
  "link_suggestions",
  "merge_note",
  "move_note",
  "start_presentation",
  "toggle_recording",
  "unlink",
} do
  add_builtin(name, function(...)
    local action = require("obsidian.actions")[name]
    action(...)
  end)
end

---@class obsidian.lsp.BlockReferenceArgs
---@field target_path string
---@field target_bufnr integer?
---@field target_range lsp.Range
---@field target_checksum string
---@field block_id string
---@field placement "inline"|"list-item"|"standalone"
---@field indent string?
---@field source_bufnr integer
---@field source_range lsp.Range
---@field source_text string
---@field placeholder string

-- Continuations are internal LSP adapters, not scripting actions.
add_builtin("block_reference_new", function(args)
  ---@cast args obsidian.lsp.BlockReferenceArgs?
  if not args then
    return
  end
  local Range = require "obsidian.range"
  local opts = vim.tbl_extend("force", args, {
    target_range = Range.from_lsp(args.target_range, "utf-8"),
    source_range = Range.from_lsp(args.source_range, "utf-8"),
  }) --[[@as obsidian.block.CreateReferenceOpts]]
  require("obsidian.block").create_reference(opts)
end)

add_builtin("footnote_new", function(...)
  require("obsidian.footnotes").create(...)
end)

add_builtin("link_suggestion", function(suggestion)
  require("obsidian.note.link_suggestion").accept(nil, suggestion)
end)

add_builtin("write_note", function(note, scope)
  local Note = require "obsidian.note"
  -- Command payloads can round-trip through clients without Lua metatables.
  if not Note.is_note_obj(note) then
    note = Note.from_table(note)
    if note.path then
      note.path = setmetatable(note.path, require "obsidian.path")
    end
  end
  note:write_new(scope)
end)

--- The built-in server commands advertised at initialization. Custom code actions
--- can be registered later; their responses carry the command ID to the client.
---@return string[]
function M.advertised()
  local ids = vim.tbl_keys(builtins)
  table.sort(ids)
  return ids
end

function M.install_client_commands()
  for id, builtin in pairs(builtins) do
    vim.lsp.commands[id] = (custom[id] or builtin).client
  end
end

--- Register an `obsidian.*` command without adding it to the code action menu.
---@param name string Command name without the `obsidian.` prefix.
---@param fn function
---@return fun() unregister
function M.register(name, fn)
  local id = "obsidian." .. name
  local entry = handler(fn)
  custom[id] = entry
  vim.lsp.commands[id] = entry.client

  return function()
    if custom[id] == entry then
      custom[id] = nil
      if vim.lsp.commands[id] == entry.client then
        vim.lsp.commands[id] = builtins[id] and builtins[id].client or nil
      end
    end
  end
end

--- Server fallback for clients that do not execute commands via vim.lsp.commands.
---@param params lsp.ExecuteCommandParams
---@return lsp.ResponseError?
function M.execute(params)
  local entry = custom[params.command] or builtins[params.command]
  if not entry then
    return { code = -32601, message = "command not found: " .. params.command }
  end

  local ok, err = pcall(entry.run, unpack(params.arguments or {}))
  if not ok then
    return { code = -32603, message = "command failed: " .. tostring(err) }
  end
end

return M
