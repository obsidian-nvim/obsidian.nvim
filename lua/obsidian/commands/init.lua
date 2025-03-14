local iter = require("obsidian.itertools").iter
local log = require "obsidian.log"

local command_lookups = {
  check = "obsidian.commands.check",
  togglecheckbox = "obsidian.commands.toggle_checkbox",
  today = "obsidian.commands.today",
  yesterday = "obsidian.commands.yesterday",
  tomorrow = "obsidian.commands.tomorrow",
  dailies = "obsidian.commands.dailies",
  new = "obsidian.commands.new",
  open = "obsidian.commands.open",
  backlinks = "obsidian.commands.backlinks",
  search = "obsidian.commands.search",
  tags = "obsidian.commands.tags",
  template = "obsidian.commands.template",
  newfromtemplate = "obsidian.commands.new_from_template",
  quickswitch = "obsidian.commands.quick_switch",
  linknew = "obsidian.commands.link_new",
  link = "obsidian.commands.link",
  links = "obsidian.commands.links",
  followlink = "obsidian.commands.follow_link",
  workspace = "obsidian.commands.workspace",
  rename = "obsidian.commands.rename",
  pasteimg = "obsidian.commands.paste_img",
  extractnote = "obsidian.commands.extract_note",
  debug = "obsidian.commands.debug",
  toc = "obsidian.commands.toc",
}

local M = setmetatable({
  commands = {},
}, {
  __index = function(t, k)
    local require_path = command_lookups[k]
    if not require_path then
      return
    end

    local mod = require(require_path)
    t[k] = mod

    return mod
  end,
})

---@class obsidian.CommandConfig
---@field opts table
---@field complete function|?
---@field func function|? (obsidian.Client, table) -> nil

---Register a new command.
---@param name string
---@param config obsidian.CommandConfig
M.register = function(name, config)
  if not config.func then
    config.func = function(client, data)
      return M[name](client, data)
    end
  end
  M.commands[name] = config
end

---Install all commands.
---
---@param client obsidian.Client
M.install = function(client)
  vim.api.nvim_create_user_command("Obsidian", function(data)
    M.handle_command(client, data)
  end, {
    nargs = "+",
    complete = function(_, cmdline, _)
      return M.get_completions(client, cmdline)
    end,
    range = 2,
  })
end

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

  local exp_nargs = cmdconfig.opts.nargs
  local range_allowed = cmdconfig.opts.range

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
    return vim.tbl_keys(M.commands)
  end
  if cmdline:match(obspat .. "%s%S+$") then
    return vim.tbl_filter(function(s)
      return s:sub(1, #obsidiancmd) == obsidiancmd
    end, vim.tbl_keys(M.commands))
  end
  local cmdconfig = M.commands[obsidiancmd]
  if cmdconfig ~= nil and cmdline:match(obspat .. "%s%S*%s%S*$") then
    if cmdconfig.complete ~= nil then
      return cmdconfig.complete(client, table.concat(vim.list_slice(splitcmd, 3), " "))
    end
    if cmdconfig.opts.complete ~= nil then
      return vim.fn.getcompletion("", cmdconfig.opts.complete)
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

M.register("check", { opts = { nargs = 0, desc = "Check for issues in your vault" } })

M.register("today", { opts = { nargs = "?", desc = "Open today's daily note" } })

M.register("yesterday", { opts = { nargs = 0, desc = "Open the daily note for the previous working day" } })

M.register("tomorrow", { opts = { nargs = 0, desc = "Open the daily note for the next working day" } })

M.register("dailies", { opts = { nargs = "*", desc = "Open a picker with daily notes" } })

M.register("new", { opts = { nargs = "?", complete = "file", desc = "Create a new note" } })

M.register("open", { opts = { nargs = "?", desc = "Open in the Obsidian app" }, complete = M.note_complete })

M.register("backlinks", { opts = { nargs = 0, desc = "Collect backlinks" } })

M.register("tags", { opts = { nargs = "*", range = true, desc = "Find tags" } })

M.register("search", { opts = { nargs = "?", desc = "Search vault" } })

M.register("template", { opts = { nargs = "?", desc = "Insert a template" } })

M.register("newfromtemplate", { opts = { nargs = "?", desc = "Create a new note from a template" } })

M.register("quickswitch", { opts = { nargs = "?", desc = "Switch notes" } })

M.register("linknew", { opts = { nargs = "?", range = true, desc = "Link selected text to a new note" } })

M.register("link", {
  opts = { nargs = "?", range = true, desc = "Link selected text to an existing note" },
  complete = M.note_complete,
})

M.register("links", { opts = { nargs = 0, desc = "Collect all links within the current buffer" } })

M.register("followlink", { opts = { nargs = "?", desc = "Follow reference or link under cursor" } })

M.register("togglecheckbox", { opts = { nargs = 0, desc = "Toggle checkbox" } })

M.register("workspace", { opts = { nargs = "?", desc = "Check or switch workspace" } })

M.register(
  "rename",
  { opts = { nargs = "?", complete = "file", desc = "Rename note and update all references to it" } }
)

M.register("pasteimg", { opts = { nargs = "?", complete = "file", desc = "Paste an image from the clipboard" } })

M.register(
  "extractnote",
  { opts = { nargs = "?", range = true, desc = "Extract selected text to a new note and link to it" } }
)

M.register("debug", { opts = { nargs = 0, desc = "Log some information for debugging" } })

M.register("toc", { opts = { nargs = 0, desc = "Load the table of contents into a picker" } })

return M
