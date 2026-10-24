local log = require "obsidian.log"
local legacycommands = require "obsidian.commands.init-legacy"
local picker = require "obsidian.picker"

---@class obsidian.commands.Context
---@field bufnr integer Originating buffer.
---@field in_note boolean Whether the buffer is marked as an Obsidian buffer.
---@field has_range boolean Whether an explicit Ex range was supplied.

---@alias obsidian.commands.Nargs integer|'0'|'1'|'?'|'+'|'*'

---@class obsidian.commands.Spec
---@field name string Unique subcommand name.
---@field fn fun(data: obsidian.commands.Args)
---@field cond? fun(ctx: obsidian.commands.Context): boolean Checked for discovery and execution; must not have side effects.
---@field complete? function|string
---@field nargs? obsidian.commands.Nargs Defaults to zero arguments.
---@field range? boolean Accept an explicit range (not a visibility condition).

---@alias obsidian.CommandsModule obsidian.commands.Module
---@class obsidian.commands.Module
---@field commands table<string, obsidian.commands.Spec>
local M = { commands = {} }

---Add or replace a command. Handlers are always supplied explicitly.
---@param spec obsidian.commands.Spec
M.add = function(spec)
  vim.validate("spec", spec, "table")
  vim.validate("name", spec.name, function(name)
    return type(name) == "string" and name:match "^[%w_%-]+$" ~= nil
  end, "a nonempty subcommand name without whitespace")
  vim.validate("fn", spec.fn, "function")
  vim.validate("cond", spec.cond, "function", true)
  vim.validate("complete", spec.complete, { "function", "string" }, true)
  vim.validate("range", spec.range, "boolean", true)
  vim.validate("nargs", spec.nargs, function(nargs)
    return nargs == nil
      or (type(nargs) == "number" and nargs >= 0 and nargs == math.floor(nargs))
      or nargs == "0"
      or nargs == "1"
      or nargs == "?"
      or nargs == "+"
      or nargs == "*"
  end, "a nonnegative integer, '0', '1', '?', '+', or '*'")
  assert(
    rawget(spec, "func") == nil and rawget(spec, "note_action") == nil,
    "Use fn and cond instead of func and note_action"
  )

  M.commands[spec.name] = vim.tbl_extend("force", { nargs = 0 }, spec)
end

---Remove a command. Removing an unknown name is a no-op.
---@param name string
M.del = function(name)
  M.commands[name] = nil
end

---@alias obsidian.CommandConfig obsidian.commands.Config
---@class obsidian.commands.Config
---@field complete? function|string
---@field nargs? obsidian.commands.Nargs
---@field range? boolean
---@field func? fun(data: obsidian.commands.Args)
---@field name? string
---@field note_action? boolean
---@field cond? fun(ctx: obsidian.commands.Context): boolean

---Register a command using the deprecated filename-based API.
---@deprecated Use commands.add { name = name, fn = handler, ... } instead.
---@param name string
---@param config obsidian.commands.Config
M.register = function(name, config)
  log.warn_once "register_command()/commands.register() is deprecated; use commands.add { name = ..., fn = ... } instead"
  local cond = config.cond
  if config.note_action then
    cond = function(ctx)
      return ctx.in_note and (config.cond == nil or config.cond(ctx))
    end
  end
  M.add {
    name = name,
    fn = config.func or function(data)
      return require("obsidian.commands." .. name)(data)
    end,
    cond = cond,
    complete = config.complete,
    nargs = config.nargs,
    range = config.range,
  }
end

M.install_legacy = legacycommands.install

---@param has_range boolean
---@return obsidian.commands.Context
local function context(has_range)
  local bufnr = vim.api.nvim_get_current_buf()
  return {
    bufnr = bufnr,
    in_note = vim.b[bufnr].obsidian_buffer == true,
    has_range = has_range,
  }
end

---@param spec obsidian.commands.Spec
---@param ctx obsidian.commands.Context
---@return boolean
local function available(spec, ctx)
  if ctx.has_range and not spec.range then
    return false
  end
  if not spec.cond then
    return true
  end
  local ok, result = pcall(spec.cond, ctx)
  if ok and type(result) == "boolean" then
    return result
  end
  log.warn_once("Command '%s' condition failed: %s", spec.name, ok and "expected a boolean result" or result)
  return false
end

---@param ctx obsidian.commands.Context
---@return string[]
local function get_commands_by_context(ctx)
  local choices = {}
  for name, spec in pairs(M.commands) do
    if available(spec, ctx) then
      choices[#choices + 1] = name
    end
  end
  table.sort(choices)
  return choices
end

---@param data obsidian.commands.Args
function M.show_menu(data)
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()
  local args = vim.deepcopy(data)
  local choices = get_commands_by_context(context(data.range > 0))

  picker.select(
    choices,
    { prompt = "Obsidian Commands" },
    vim.schedule_wrap(function(items)
      local item = items[1]
      if not item then
        vim.notify("Aborted", 3)
        return
      end
      if not vim.api.nvim_buf_is_valid(bufnr) or not vim.api.nvim_buf_is_loaded(bufnr) then
        log.err "Command buffer is no longer available"
        return
      end
      if vim.api.nvim_win_is_valid(winid) and vim.api.nvim_win_get_buf(winid) == bufnr then
        vim.api.nvim_set_current_win(winid)
      else
        vim.api.nvim_set_current_buf(bufnr)
      end
      local selected_args = vim.deepcopy(args)
      table.insert(selected_args.fargs, 1, item)
      M.handle_command(selected_args)
    end)
  )
end

---@param data obsidian.commands.Args
M.handle_command = function(data)
  data = vim.deepcopy(data)
  local cmd = table.remove(data.fargs, 1)
  data.args = table.concat(data.fargs, " ")
  local nargs = #data.fargs
  local spec = M.commands[cmd]
  if spec == nil then
    log.err("Command '" .. tostring(cmd) .. "' not found")
    return
  end

  if data.range > 0 and not spec.range then
    log.err("Command '" .. cmd .. "' does not accept a range")
    return
  end
  if not available(spec, context(data.range > 0)) then
    log.err("Command '" .. cmd .. "' is not available in this context")
    return
  end

  local exp_nargs = spec.nargs
  if exp_nargs == "?" then
    if nargs > 1 then
      log.err("Command '" .. cmd .. "' expects 0 or 1 arguments, but " .. nargs .. " were provided")
      return
    end
  elseif exp_nargs == "+" then
    if nargs == 0 then
      log.err("Command '" .. cmd .. "' expects at least one argument, but none were provided")
      return
    end
  elseif exp_nargs ~= "*" and tonumber(exp_nargs) ~= nargs then
    log.err("Command '" .. cmd .. "' expects " .. exp_nargs .. " arguments, but " .. nargs .. " were provided")
    return
  end

  spec.fn(data)
end

---@param arg_lead string
---@param cmdline string
---@param cursor_pos integer
M.get_completions = function(arg_lead, cmdline, cursor_pos)
  local prefix, tail = cmdline:sub(1, cursor_pos):match "^%s*:?(.-)Obsidian!?%s+(.*)$"
  if not prefix or not tail then
    return {}
  end
  local ctx = context(vim.trim(prefix) ~= "")
  local name = tail:match "^(%S+)" or ""
  if not tail:match "^%S+%s" then
    return vim.tbl_filter(function(choice)
      return vim.startswith(choice, name)
    end, get_commands_by_context(ctx))
  end

  local spec = M.commands[name]
  if not spec or not available(spec, ctx) then
    return {}
  end
  if type(spec.complete) == "function" then
    return spec.complete(arg_lead, cmdline, cursor_pos)
  end
  if type(spec.complete) == "string" then
    local cmd_arg = tail:match "^%S+%s+(.*)$" or ""
    return vim.fn.getcompletion(cmd_arg, spec.complete)
  end
  return {}
end

---@param _ string
---@param cmdline string
---@return string[]
M.help_complete = function(_, cmdline)
  local api = require "obsidian.api"
  local docs_dir = api.docs_dir()
  if not docs_dir then
    return {}
  end

  local query = cmdline:match "^%S+%s%S+%s(.*)$" or ""

  local files = vim.fn.globpath(tostring(docs_dir), "*.md", true, true)
  local basenames = vim.tbl_map(function(path)
    return vim.fn.fnamemodify(path, ":t:r")
  end, files)

  if query == "" then
    return basenames
  end

  return vim.fn.matchfuzzy(basenames, query, { limit = 10 })
end

---@param _ string
---@param cmdline string
---@return string[]
M.note_complete = function(_, cmdline)
  local search = require "obsidian.search"
  local completions = {}

  local query = cmdline:match "^%S+%s%S+%s(.*)$" or ""

  if query == "" then
    return {}
  end

  -- if there's already partial query that ended with a space, then we should search for the query instead of note names
  local query_results = search.find_notes(query, {})

  for _, note in ipairs(query_results) do
    local path = note.path
    ---@cast path -nil
    local note_path = path:vault_relative_path { strict = true }
    ---@cast note_path -nil
    table.insert(completions, note:display_name() .. "  " .. tostring(note_path))
    if not vim.tbl_isempty(note.aliases) then
      for _, alias in pairs(note.aliases) do
        table.insert(completions, alias .. "  " .. tostring(note_path))
      end
    end
  end

  completions = vim.fn.matchfuzzy(completions, query, { limit = 10 })
  return completions
end

require "obsidian.commands.builtin"(M)

return M
