local iter = vim.iter
local log = require "obsidian.log"
local legacycommands = require "obsidian.commands.init-legacy"
local search = require "obsidian.search"

local M = { commands = {} }

local function in_note()
  return vim.bo.filetype == "markdown"
end

---@param commands obsidian.CommandConfig[]
---@param is_visual boolean
---@param is_note boolean
---@return string[]
local function get_commands_by_context(commands, is_visual, is_note)
  local choices = vim.tbl_values(commands)
  return vim
    .iter(choices)
    :filter(function(config)
      if is_visual then
        return config.range ~= nil
      else
        return config.range == nil
      end
    end)
    :filter(function(config)
      if is_note then
        return true
      else
        return not config.note_action
      end
    end)
    :map(function(config)
      return config.name
    end)
    :totable()
end

local function show_menu(data)
  local is_visual, is_note = data.range ~= 0, in_note()
  local choices = get_commands_by_context(M.commands, is_visual, is_note)

  vim.ui.select(
    choices,
    { prompt = "Obsidian Commands" },
    vim.schedule_wrap(function(item)
      if item then
        return vim.cmd.Obsidian(item)
      else
        vim.notify("Aborted", 3)
      end
    end)
  )
end

---@class obsidian.CommandConfig
---@field complete function|string|?
---@field nargs string|integer|?
---@field range boolean|?
---@field func fun(data: obsidian.CommandArgs)?
---@field name string?
---@field note_action boolean?

---Register a new command.
---@param name string
---@param config obsidian.CommandConfig
M.register = function(name, config)
  if not config.func then
    config.func = function(data)
      local mod = require("obsidian.commands." .. name)
      return mod(data)
    end
  end
  config.name = name
  M.commands[name] = config
end

---Install all commands.
---
---@param opts obsidian.config.Internal
M.install = function(opts)
  ------------------------
  ---- general action ----
  ------------------------

  M.register("check", { nargs = 0 })

  M.register("new", { nargs = "*" })

  M.register("open", { nargs = "?", complete = M.note_complete })

  M.register("tags", { nargs = "*" })

  M.register("search", { nargs = "?" })

  M.register("quick_switch", { nargs = "?" })

  M.register("workspace", { nargs = "?" })

  if opts.daily_notes.enabled then
    M.register("today", { nargs = "?" })
    M.register("yesterday", { nargs = 0 })
    M.register("tomorrow", { nargs = 0 })
    M.register("dailies", { nargs = "*" })
  end

  if opts.templates.enabled then
    M.register("new_from_template", { nargs = "*" })
  end

  ---------------------
  ---- note action ----
  ---------------------

  if opts.templates.enabled then
    M.register("template", { nargs = "?", note_action = true })
  end

  M.register("backlinks", { nargs = 0, note_action = true })

  M.register("link_new", { mode = "v", nargs = "?", range = true, note_action = true })

  M.register("link", { nargs = "?", range = true, complete = M.note_complete, note_action = true })

  M.register("links", { nargs = 0, note_action = true })

  M.register("follow_link", { nargs = "?", note_action = true })

  M.register("toggle_checkbox", { nargs = 0, range = true, note_action = true })

  M.register("rename", { nargs = "?", note_action = true })

  M.register("paste_img", { nargs = "?", note_action = true })

  M.register("extract_note", { mode = "v", nargs = "?", range = true, note_action = true })

  M.register("toc", { nargs = 0, note_action = true })

  vim.api.nvim_create_user_command("Obsidian", function(data)
    if #data.fargs == 0 then
      show_menu(data)
      return
    end
    M.handle_command(data)
  end, {
    nargs = "*",
    complete = function(_, cmdline, _)
      return M.get_completions(cmdline)
    end,
    range = 2,
  })
end

M.install_legacy = legacycommands.install

M.handle_command = function(data)
  local cmd = data.fargs[1]
  table.remove(data.fargs, 1)
  data.args = table.concat(data.fargs, " ")
  local nargs = #data.fargs

  local cmdconfig = M.commands[cmd]
  if cmdconfig == nil then
    log.err("Command '" .. cmd .. "' not found")
    return
  end

  local exp_nargs = cmdconfig.nargs
  local range_allowed = cmdconfig.range

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
  elseif exp_nargs ~= "*" and exp_nargs ~= nargs then
    log.err("Command '" .. cmd .. "' expects " .. exp_nargs .. " arguments, but " .. nargs .. " were provided")
    return
  end

  if not range_allowed and data.range > 0 then
    log.error("Command '" .. cmd .. "' does not accept a range")
    return
  end

  cmdconfig.func(data)
end

---@param cmdline string
M.get_completions = function(cmdline)
  local obspat = "^['<,'>]*Obsidian[!]?"
  local splitcmd = vim.split(cmdline, " ", { plain = true, trimempty = true })
  local obsidiancmd = splitcmd[2]
  if cmdline:match(obspat .. "%s$") then
    local is_visual = vim.startswith(cmdline, "'<,'>")
    return get_commands_by_context(M.commands, is_visual, in_note())
  end
  if cmdline:match(obspat .. "%s%S+$") then
    return vim.tbl_filter(function(s)
      return s:sub(1, #obsidiancmd) == obsidiancmd
    end, vim.tbl_keys(M.commands))
  end
  local cmdconfig = M.commands[obsidiancmd]
  if cmdconfig == nil then
    return
  end
  if cmdline:match(obspat .. "%s%S*%s%S*$") then
    local cmd_arg = table.concat(vim.list_slice(splitcmd, 3), " ")
    local complete_type = type(cmdconfig.complete)
    if complete_type == "function" then
      return cmdconfig.complete(cmd_arg)
    end
    if complete_type == "string" then
      return vim.fn.getcompletion(cmd_arg, cmdconfig.complete)
    end
  end
end

--TODO: Note completion is currently broken (see: https://github.com/epwalsh/obsidian.nvim/issues/753)
---@return string[]
M.note_complete = function(cmd_arg)
  local query
  if string.len(cmd_arg) > 0 then
    if string.find(cmd_arg, "|", 1, true) then
      return {}
    else
      query = cmd_arg
    end
  else
    local _, csrow, cscol, _ = unpack(assert(vim.fn.getpos "'<"))
    local _, cerow, cecol, _ = unpack(assert(vim.fn.getpos "'>"))
    local lines = vim.fn.getline(csrow, cerow)
    assert(type(lines) == "table", "")

    if #lines > 1 then
      lines[1] = string.sub(lines[1], cscol)
      lines[#lines] = string.sub(lines[#lines], 1, cecol)
    elseif #lines == 1 then
      lines[1] = string.sub(lines[1], cscol, cecol)
    else
      return {}
    end

    query = table.concat(lines, " ")
  end

  local completions = {}
  local query_lower = string.lower(query)
  for note in iter(search.find_notes(query, { search = { sort = true } })) do
    local note_path = assert(note.path:vault_relative_path { strict = true })
    if string.find(string.lower(note:display_name()), query_lower, 1, true) then
      table.insert(completions, note:display_name() .. "  " .. tostring(note_path))
    else
      for _, alias in pairs(note.aliases) do
        if string.find(string.lower(alias), query_lower, 1, true) then
          table.insert(completions, alias .. "  " .. tostring(note_path))
          break
        end
      end
    end
  end

  return completions
end

return M
