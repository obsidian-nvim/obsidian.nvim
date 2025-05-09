local iter = vim.iter
local log = require "obsidian.log"
local legacycommands = require "obsidian.commands.init-legacy"

local M = { commands = {} }

local note_action = {
  backlinks = true,
  template = true,
  link_new = true,
  link = true, -- TODO: ???
  links = true,
  follow_link = true,
  toggle_checkbox = true,
  rename = true,
  paste_img = true,
  extract_note = true,
  toc = true,
}

local function in_note()
  local buf = vim.api.nvim_get_current_buf()
  return vim.bo[buf].filetype == "markdown"
end

local function get_commands(choices, is_visual, is_note)
  choices = vim.tbl_filter(function(config)
    if is_visual then
      return config.range ~= nil
    else
      return config.range == nil
    end
  end, choices)

  choices = vim.tbl_filter(function(config)
    if is_note then
      return true
    else
      return not note_action[config.name]
    end
  end, choices)
  return choices
end

-- TODO: this will be context-sensitive in the future
local function show_menu(data)
  local is_visual, is_note = data.range ~= 0, in_note()
  local choices = get_commands(M.commands, is_visual, is_note)

  vim.ui.select(choices, {
    prompt = "Obsidian Commands",
    format_item = function(item)
      return item.name
    end,
  }, function(item)
    if item then
      return vim.cmd.Obsidian(item.name)
    else
      vim.notify("Aborted", 3)
    end
  end)
end

---@class obsidian.CommandConfig
---@field complete function|string|?
---@field nargs string|integer|?
---@field range boolean|?
---@field func function|? (obsidian.Client, table) -> nil
---@field name string?

---Register a new command.
---@param name string
---@param config obsidian.CommandConfig
M.register = function(name, config)
  if not config.func then
    config.func = function(client, data)
      local mod = require("obsidian.commands." .. name)
      return mod(client, data)
    end
  end
  config.name = name
  M.commands[name] = config
end

---Install all commands.
---
---@param client obsidian.Client
M.install = function(client)
  vim.api.nvim_create_user_command("Obsidian", function(data)
    if #data.fargs == 0 then
      show_menu(data)
      return
    end
    M.handle_command(client, data)
  end, {
    nargs = "*",
    complete = function(_, cmdline, _)
      return M.get_completions(client, cmdline)
    end,
    range = 2,
  })
end

M.install_legacy = legacycommands.install

---@param client obsidian.Client
M.handle_command = function(client, data)
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

  cmdconfig.func(client, data)
end

---@param client obsidian.Client
---@param cmdline string
M.get_completions = function(client, cmdline)
  local obspat = "^['<,'>]*Obsidian[!]?"
  local splitcmd = vim.split(cmdline, " ", { plain = true, trimempty = true })
  local obsidiancmd = splitcmd[2]
  if cmdline:match(obspat .. "%s$") then
    local is_visual = vim.startswith(cmdline, "'<,'>")
    local choices = get_commands(M.commands, is_visual, in_note())

    return vim.tbl_map(function(item)
      return item.name
    end, choices)
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
      return cmdconfig.complete(client, cmd_arg)
    end
    if complete_type == "string" then
      return vim.fn.getcompletion(cmd_arg, cmdconfig.complete)
    end
  end
end

--TODO: Note completion is currently broken (see: https://github.com/epwalsh/obsidian.nvim/issues/753)
---@param client obsidian.Client
---@return string[]
M.note_complete = function(client, cmd_arg)
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
    assert(type(lines) == "table")

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
  for note in iter(client:find_notes(query, { search = { sort = true } })) do
    local note_path = assert(client:vault_relative_path(note.path, { strict = true }))
    if string.find(string.lower(note:display_name()), query_lower, 1, true) then
      table.insert(completions, note:display_name() .. "  " .. note_path)
    else
      for _, alias in pairs(note.aliases) do
        if string.find(string.lower(alias), query_lower, 1, true) then
          table.insert(completions, alias .. "  " .. note_path)
          break
        end
      end
    end
  end

  return completions
end

M.register("check", { nargs = 0 })

M.register("today", { nargs = "?" })

M.register("yesterday", { nargs = 0 })

M.register("tomorrow", { nargs = 0 })

M.register("dailies", { nargs = "*" })

M.register("new", { nargs = "?" })

M.register("open", { nargs = "?", complete = M.note_complete })

M.register("backlinks", { nargs = 0 })

M.register("tags", { nargs = "*", range = true })

M.register("search", { nargs = "?" })

M.register("template", { nargs = "?" })

M.register("new_from_template", { nargs = "*" })

M.register("quick_switch", { nargs = "?" })

M.register("link_new", { mode = "v", nargs = "?", range = true })

M.register("link", { nargs = "?", range = true, complete = M.note_complete })

M.register("links", { nargs = 0 })

M.register("follow_link", { nargs = "?" })

M.register("toggle_checkbox", { nargs = 0, range = true })

M.register("workspace", { nargs = "?" })

M.register("rename", { nargs = "?" })

M.register("paste_img", { nargs = "?" })

M.register("extract_note", { mode = "v", nargs = "?", range = true })

M.register("debug", { nargs = 0 })

M.register("toc", { nargs = 0 })

return M
