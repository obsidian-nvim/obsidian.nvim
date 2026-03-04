local log = require "obsidian.log"

local M = {}

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
      params[vim.uri_decode(key)] = vim.uri_decode(value)
    else
      -- Bare key with no value, e.g. &silent&
      params[vim.uri_decode(pair)] = "true"
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

  if hash_pos ~= nil then
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
    params = { path = vim.uri_decode(rest) }
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
      local decoded = vim.uri_decode(before_q)
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

--- Dispatch a parsed URI to the appropriate action handler.
---
---@param parsed obsidian.uri.Parsed
M.dispatch = function(parsed)
  local ok, handler = pcall(require, "obsidian.uri.handlers." .. parsed.action)
  if ok and handler ~= nil then
    if not resolve_vault(parsed) then
      return
    end
    handler(parsed)
  else
    log.err("Unsupported obsidian:// action: '%s'", parsed.action)
  end
end

--- Parse and handle an obsidian:// URI string.
---
---@param uri string
M.handle = function(uri)
  vim.fn.writefile({ uri }, "/home/n451/obsidian-uri-debug.txt", "a") -- debug log
  local parsed = M.parse(uri)
  if parsed then
    M.dispatch(parsed)
  end
end

return M
