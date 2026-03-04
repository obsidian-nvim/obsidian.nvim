local log = require "obsidian.log"

local M = {}

--- URL-decode a percent-encoded string.
---@param s string
---@return string
local function urldecode(s)
  s = s:gsub("+", " ")
  s = s:gsub("%%(%x%x)", function(hex)
    return string.char(tonumber(hex, 16))
  end)
  return s
end

--- Parse query string into a table of key=value pairs.
--- Values are URL-decoded. Keys appearing without a value are set to "true".
---
---@param qs string
---@return table<string, string>
local function parse_query(qs)
  local params = {}
  if not qs or qs == "" then
    return params
  end
  for pair in qs:gmatch "[^&]+" do
    local key, value = pair:match "^([^=]+)=(.*)$"
    if key then
      params[urldecode(key)] = urldecode(value)
    else
      -- Bare key with no value, e.g. &silent&
      params[urldecode(pair)] = "true"
    end
  end
  return params
end

--- Split a file reference into the file part and an optional anchor/block fragment.
--- e.g. "path/to/Note#Heading" -> "path/to/Note", "#Heading"
--- e.g. "path/to/Note#^block" -> "path/to/Note", "#^block"
---
---@param file string
---@return string file_part
---@return string|? anchor The anchor string including the leading '#', or nil.
local function split_fragment(file)
  -- Match the last '#' that isn't part of a percent-encoded sequence.
  -- Walk backward to find the fragment separator.
  local hash_pos = nil
  local i = 1
  while i <= #file do
    local c = file:sub(i, i)
    if c == "%" and i + 2 <= #file then
      -- Skip percent-encoded triplet.
      i = i + 3
    elseif c == "#" then
      hash_pos = i
      i = i + 1
    else
      i = i + 1
    end
  end

  if hash_pos then
    local file_part = file:sub(1, hash_pos - 1)
    local anchor = file:sub(hash_pos) -- includes the '#'
    return file_part, anchor
  end

  return file, nil
end

---@class obsidian.uri.Parsed
---
---@field action string The URI action: "open", "new", "daily", "unique", "search", "choose-vault", "hook-get-address".
---@field params table<string, string> All raw decoded query parameters.
---
--- Convenience fields derived from params:
---@field vault string|? Vault name or ID.
---@field file string|? File path relative to vault root.
---@field path string|? Absolute filesystem path.
---@field name string|? File name for new notes.
---@field content string|? Note content.
---@field query string|? Search query.
---@field anchor string|? Heading anchor or block reference (e.g. "#Heading" or "#^block-id").
---@field clipboard boolean Use clipboard as content source.
---@field silent boolean Don't open the created note.
---@field append boolean Append to existing file.
---@field prepend boolean Prepend to existing file.
---@field overwrite boolean Overwrite existing file.
---@field pane_type string|? "tab", "split", or "window".
---@field x_success string|? x-callback-url success callback.
---@field x_error string|? x-callback-url error callback.

--- Parse an `obsidian://` URI string into a structured table.
---
--- Supports all documented forms:
---   Standard:   obsidian://action?param1=value&param2=value
---   Shorthand:  obsidian://vault/my vault/my note
---   Absolute:   obsidian:///absolute/path/to/note
---
---@param uri string
---@return obsidian.uri.Parsed|? parsed Returns nil on parse failure.
M.parse = function(uri)
  -- Strip the scheme.
  local rest = uri:match "^obsidian://(.*)$"
  if not rest then
    log.err("Not an obsidian:// URI: %s", uri)
    return nil
  end

  local action, params

  -- Shorthand: obsidian:///absolute/path  (triple slash -> absolute path)
  if rest:sub(1, 1) == "/" then
    action = "open"
    params = { path = urldecode(rest) }
  else
    -- Split on '?' to separate action from query string.
    local before_q, qs = rest:match "^([^?]*)%?(.*)$"
    if not before_q then
      before_q = rest
      qs = nil
    end

    -- Check if this is a known action or a shorthand vault/file form.
    local known_actions = {
      open = true,
      new = true,
      daily = true,
      unique = true,
      search = true,
      ["choose-vault"] = true,
      ["hook-get-address"] = true,
    }

    if known_actions[before_q] then
      -- Standard form: obsidian://action?params
      action = before_q
      params = parse_query(qs)
    elseif qs then
      -- Has query params but action isn't known -> could be an advanced-uri or plugin action.
      -- Still try to parse it as action + params.
      action = before_q
      params = parse_query(qs)
    else
      -- Shorthand: obsidian://vault/path/to/note
      action = "open"
      local decoded = urldecode(before_q)
      local vault, file = decoded:match "^([^/]+)/(.+)$"
      if vault then
        params = { vault = vault, file = file }
      else
        -- Just a vault name with no file.
        params = { vault = decoded }
      end
    end
  end

  -- Extract the anchor/block fragment from the file parameter.
  local anchor = nil
  if params.file then
    local file_part, frag = split_fragment(params.file)
    params.file = file_part
    anchor = frag
  end
  if params.path then
    local path_part, frag = split_fragment(params.path)
    params.path = path_part
    if not anchor then
      anchor = frag
    end
  end

  -- Strip .md extension from file if present.
  if params.file and params.file:match "%.md$" then
    params.file = params.file:sub(1, -4)
  end

  ---@type obsidian.uri.Parsed
  local parsed = {
    action = action,
    params = params,
    vault = params.vault,
    file = params.file,
    path = params.path,
    name = params.name,
    content = params.content,
    query = params.query,
    anchor = anchor,
    clipboard = params.clipboard ~= nil,
    silent = params.silent ~= nil,
    append = params.append ~= nil,
    prepend = params.prepend ~= nil,
    overwrite = params.overwrite ~= nil,
    pane_type = params.paneType,
    x_success = params["x-success"],
    x_error = params["x-error"],
  }

  return parsed
end

--- Map a URI paneType to a Neovim open command.
---
---@param pane_type string|?
---@return string|? vim_cmd
local function pane_type_to_open_strategy(pane_type)
  if not pane_type then
    return nil
  end
  local map = {
    tab = "tabedit",
    split = "split",
    window = "vsplit", -- no pop-out window in nvim, closest approximation
  }
  local cmd = map[pane_type]
  if not cmd then
    log.warn("Unknown paneType '%s', ignoring", pane_type)
  end
  return cmd
end

--- Resolve which workspace matches the vault parameter and switch to it.
--- Returns true if resolution succeeded (or no vault was specified).
---
---@param parsed obsidian.uri.Parsed
---@return boolean
local function resolve_vault(parsed)
  if not parsed.vault then
    return true -- use current workspace
  end

  local Workspace = require "obsidian.workspace"

  for _, ws in ipairs(Obsidian.workspaces) do
    if ws.name == parsed.vault or vim.fs.basename(tostring(ws.path)) == parsed.vault then
      Workspace.set(ws)
      return true
    end
  end

  -- Check if it looks like a hex vault ID.
  if parsed.vault:match "^%x+$" and #parsed.vault == 16 then
    log.warn("Vault ID '%s' is not supported by obsidian.nvim, use vault name instead", parsed.vault)
  else
    log.err("Vault '%s' not found in configured workspaces", parsed.vault)
  end

  return false
end

-----------------------
--- Action handlers ---
-----------------------

--- Handle the "open" action.
---@param parsed obsidian.uri.Parsed
local function handle_open(parsed)
  if not resolve_vault(parsed) then
    return
  end

  local file_path = parsed.file or parsed.path
  if not file_path then
    -- Just open/switch to the vault, nothing more to do.
    log.info("Switched to vault '%s'", Obsidian.workspace.name)
    return
  end

  local Path = require "obsidian.path"
  local Note = require "obsidian.note"
  local api = require "obsidian.api"

  ---@type obsidian.Path
  local note_path
  if parsed.path then
    -- Absolute path: use directly.
    note_path = Path.new(parsed.path)
  else
    -- Relative to vault root. Try with and without .md extension.
    note_path = Obsidian.dir / (parsed.file .. ".md")
    if not note_path:is_file() then
      note_path = Obsidian.dir / parsed.file
    end
  end

  if not note_path:is_file() then
    log.err("Note not found: %s", tostring(note_path))
    return
  end

  local open_cmd = pane_type_to_open_strategy(parsed.pane_type) or api.get_open_strategy(Obsidian.opts.open_notes_in)

  -- Open the note.
  local note = Note.from_file(note_path, { collect_anchor_links = true, collect_blocks = true })
  local open_opts = {
    sync = true,
    open_strategy = nil, -- we pass the cmd directly via api.open_note below
  }

  ---@type integer|?
  local target_line

  -- Resolve anchor or block reference.
  if parsed.anchor then
    local anchor = parsed.anchor
    if anchor:sub(1, 2) == "#^" then
      -- Block reference.
      local block_id = anchor:sub(3)
      local block = note:resolve_block(block_id)
      if block then
        target_line = block[1]
      else
        log.warn("Block '^%s' not found in note", block_id)
      end
    elseif anchor:sub(1, 1) == "#" then
      -- Heading anchor.
      local heading = anchor:sub(2)
      local resolved = note:resolve_anchor_link(heading)
      if resolved then
        target_line = resolved.line
      else
        log.warn("Heading '#%s' not found in note", heading)
      end
    end
  end

  api.open_note({
    filename = tostring(note_path),
    lnum = target_line,
  }, open_cmd)
end

--- Handle the "new" action.
---@param parsed obsidian.uri.Parsed
local function handle_new(parsed)
  if not resolve_vault(parsed) then
    return
  end

  local Note = require "obsidian.note"
  local Path = require "obsidian.path"

  -- Determine the note identity.
  local id = parsed.name or parsed.file
  local dir = nil

  if parsed.path then
    -- Absolute path: derive dir and id from it.
    local p = Path.new(parsed.path)
    dir = p:parent()
    id = tostring(p.stem)
  elseif parsed.file then
    -- file is a vault-absolute path like "path/to/note".
    -- The id already contains path components which Note._resolve_id_path handles.
    id = parsed.file
  end

  -- Determine content.
  local content = parsed.content
  if parsed.clipboard then
    content = vim.fn.getreg "+"
  end

  local note = Note.create {
    id = id,
    dir = dir,
    should_write = true,
  }

  -- Write content if provided.
  if content and content ~= "" then
    local lines = vim.split(content, "\n", { plain = true })
    local file_lines = vim.fn.readfile(tostring(note.path))
    -- Append content after the existing template content.
    vim.list_extend(file_lines, lines)
    vim.fn.writefile(file_lines, tostring(note.path))
  end

  if not parsed.silent then
    local open_cmd = pane_type_to_open_strategy(parsed.pane_type)
    note:open { sync = true, open_strategy = open_cmd }
  end
end

--- Handle the "daily" action.
---@param parsed obsidian.uri.Parsed
local function handle_daily(parsed)
  if not resolve_vault(parsed) then
    return
  end

  local daily = require "obsidian.daily"
  local note = daily.today()
  note:open { sync = true }
end

--- Handle the "unique" action. Creates a new note with an auto-generated ID.
---@param parsed obsidian.uri.Parsed
local function handle_unique(parsed)
  if not resolve_vault(parsed) then
    return
  end

  local Note = require "obsidian.note"

  local content = parsed.content
  if parsed.clipboard then
    content = vim.fn.getreg "+"
  end

  -- id = nil causes note_id_func to auto-generate a zettel ID.
  local note = Note.create {
    should_write = true,
  }

  if content and content ~= "" then
    local lines = vim.split(content, "\n", { plain = true })
    local file_lines = vim.fn.readfile(tostring(note.path))
    vim.list_extend(file_lines, lines)
    vim.fn.writefile(file_lines, tostring(note.path))
  end

  local open_cmd = pane_type_to_open_strategy(parsed.pane_type)
  note:open { sync = true, open_strategy = open_cmd }
end

--- Handle the "search" action.
---@param parsed obsidian.uri.Parsed
local function handle_search(parsed)
  if not resolve_vault(parsed) then
    return
  end

  Obsidian.picker.grep_notes {
    query = parsed.query,
  }
end

--- Handle the "choose-vault" action.
---@param _ obsidian.uri.Parsed
local function handle_choose_vault(_)
  local Workspace = require "obsidian.workspace"

  ---@type obsidian.PickerEntry[]
  local items = {}
  for _, ws in ipairs(Obsidian.workspaces) do
    if ws.name ~= ".obsidian.wiki" then
      items[#items + 1] = {
        user_data = ws,
        text = tostring(ws),
        filename = tostring(ws.path),
      }
    end
  end

  Obsidian.picker.pick(items, {
    prompt_title = "Obsidian Workspace",
    callback = function(entry)
      Workspace.set(entry.user_data)
    end,
  })
end

--- Handle the "hook-get-address" action (best-effort).
--- Copies the current note's obsidian:// URI to the clipboard.
---@param parsed obsidian.uri.Parsed
local function handle_hook_get_address(parsed)
  if not resolve_vault(parsed) then
    return
  end

  local api = require "obsidian.api"
  local util = require "obsidian.util"
  local note = api.current_note(0)
  if not note then
    log.err "No note found in current buffer"
    return
  end

  local vault_name = vim.fs.basename(tostring(Obsidian.workspace.root))
  local rel_path = note.path:vault_relative_path()
  if not rel_path then
    log.err "Could not determine vault-relative path for current note"
    return
  end

  local encoded_vault = util.urlencode(vault_name)
  local encoded_file = util.urlencode(tostring(rel_path), { keep_path_sep = true })
  local obsidian_uri = ("obsidian://open?vault=%s&file=%s"):format(encoded_vault, encoded_file)

  local display = note:display_name()
  local md_link = ("[%s](%s)"):format(display, obsidian_uri)

  vim.fn.setreg("+", md_link)
  log.info("Copied link to clipboard: %s", md_link)
end

--- Dispatch table mapping action names to handler functions.
---@type table<string, fun(parsed: obsidian.uri.Parsed)>
local handlers = {
  open = handle_open,
  new = handle_new,
  daily = handle_daily,
  unique = handle_unique,
  search = handle_search,
  ["choose-vault"] = handle_choose_vault,
  ["hook-get-address"] = handle_hook_get_address,
}

--- Dispatch a parsed URI to the appropriate action handler.
---
---@param parsed obsidian.uri.Parsed
M.dispatch = function(parsed)
  local handler = handlers[parsed.action]
  if handler then
    handler(parsed)
  else
    log.err("Unsupported obsidian:// action: '%s'", parsed.action)
  end
end

--- Parse and handle an obsidian:// URI string.
---
---@param uri string
M.handle = function(uri)
  local parsed = M.parse(uri)
  if parsed then
    M.dispatch(parsed)
  end
end

return M
