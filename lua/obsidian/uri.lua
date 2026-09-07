local Path = require "obsidian.path"
local ut = require "obsidian.uri.util"

local M = {}

local known_actions = {
  open = true,
  new = true,
  daily = true,
  unique = true,
  search = true,
  ["choose-vault"] = true,
  ["hook-get-address"] = true,
}

---@type table<string, fun(parsed: obsidian.uri.Parsed): obsidian.uri.Result>
local handlers = {
  open = function(parsed)
    return require "obsidian.uri.handlers.open"(parsed)
  end,
  new = function(parsed)
    return require "obsidian.uri.handlers.new"(parsed)
  end,
  daily = function(parsed)
    return require "obsidian.uri.handlers.daily"(parsed)
  end,
  unique = function(parsed)
    return require "obsidian.uri.handlers.unique"(parsed)
  end,
  search = function(parsed)
    return require "obsidian.uri.handlers.search"(parsed)
  end,
  ["choose-vault"] = function(parsed)
    return require "obsidian.uri.handlers.choose-vault"(parsed)
  end,
  ["hook-get-address"] = function(parsed)
    return require "obsidian.uri.handlers.hook-get-address"(parsed)
  end,
}

--- Parse query string into decoded key/value pairs.
--- Bare keys are represented as the string "true"; URI flags use presence semantics.
---
---@param qs string|?
---@return table<string, string>
local function parse_query(qs)
  local params = {}
  if not qs or qs == "" then
    return params
  end

  for pair in qs:gmatch "[^&]+" do
    local key, value = pair:match "^([^=]+)=(.*)$"
    if key and value then
      -- '+' means space in form-style query strings.
      params[vim.uri_decode(key)] = vim.uri_decode((value:gsub("+", "%%20")))
    else
      params[vim.uri_decode(pair)] = "true"
    end
  end
  return params
end

---@param value string
---@return string file
---@return string|? anchor
local function split_fragment(value)
  ---@type integer|?
  local hash_pos
  for i = 1, #value do
    if value:sub(i, i) == "#" then
      hash_pos = i
    end
  end
  if hash_pos then
    return value:sub(1, hash_pos - 1), value:sub(hash_pos)
  end
  return value, nil
end

---@class obsidian.uri.Parsed
---@field action string
---@field params table<string, string>
---@field vault string|?
---@field file string|?
---@field path string|?
---@field name string|?
---@field content string|?
---@field query string|?
---@field anchor string|?
---@field clipboard boolean
---@field silent boolean
---@field append boolean
---@field prepend boolean
---@field overwrite boolean
---@field pane_type string|?
---@field x_success string|?
---@field x_error string|?

--- Parse an `obsidian://` URI.
---
--- Supports standard, vault/file shorthand, and absolute-path shorthand forms.
---
---@param uri string
---@return obsidian.uri.Parsed|? parsed
M.parse = function(uri)
  if type(uri) ~= "string" then
    return nil
  end

  local rest = uri:match "^[Oo][Bb][Ss][Ii][Dd][Ii][Aa][Nn]://(.*)$"
  if not rest then
    return nil
  end

  local action
  ---@type table<string, string>
  local params

  if rest:sub(1, 1) == "/" then
    action = "open"
    params = { path = vim.uri_decode(rest) }
  else
    local before_q, qs = rest:match "^([^?]*)%?(.*)$"
    if before_q then
      -- A query makes the authority unambiguously an action. Unknown actions
      -- remain parseable so dispatch can return a useful unsupported result.
      action = before_q
      params = parse_query(qs)
    elseif known_actions[rest] then
      action = rest
      params = {}
    else
      action = "open"
      local decoded = vim.uri_decode(rest)
      local vault, file = decoded:match "^([^/]+)/(.+)$"
      if vault and file then
        params = { vault = vault, file = file }
      else
        params = { vault = decoded }
      end
    end
  end

  local anchor
  if params.file then
    params.file, anchor = split_fragment(params.file)
  end
  if params.path then
    local path_anchor
    params.path, path_anchor = split_fragment(params.path)
    anchor = anchor or path_anchor
  end

  if params.file and params.file:match "%.md$" then
    params.file = params.file:sub(1, -4)
  end

  return {
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
end

---@param workspace obsidian.Workspace
local function set_workspace(workspace)
  if Obsidian.workspace ~= workspace then
    require("obsidian.workspace").set(workspace)
  end
end

---@param path string
---@return obsidian.Workspace|?
local function workspace_for_path(path)
  local candidate = Path.new(path)
  if not candidate:is_absolute() then
    return nil
  end
  candidate = candidate:resolve()

  ---@type obsidian.Workspace|?
  local best
  local best_length = -1
  for _, workspace in ipairs(Obsidian.workspaces) do
    local root = Path.new(workspace.root):resolve()
    if (candidate == root or root:is_parent_of(candidate)) and #tostring(root) > best_length then
      best = workspace
      best_length = #tostring(root)
    end
  end
  return best
end

---@param parsed obsidian.uri.Parsed
---@return string|?
local function resolve_workspace(parsed)
  -- `path` overrides `vault` and `file` in the Obsidian URI contract.
  if parsed.path then
    local workspace = workspace_for_path(parsed.path)
    if not workspace then
      return ("Path is not inside a configured workspace: %s"):format(parsed.path)
    end
    set_workspace(workspace)
    return nil
  end

  if not parsed.vault then
    return nil
  end

  ---@type obsidian.Workspace|?
  local matched
  for _, workspace in ipairs(Obsidian.workspaces) do
    if workspace.name == parsed.vault then
      matched = workspace
      break
    end
  end
  if not matched then
    for _, workspace in ipairs(Obsidian.workspaces) do
      if vim.fs.basename(tostring(workspace.root)) == parsed.vault then
        matched = workspace
        break
      end
    end
  end

  if matched then
    set_workspace(matched)
    return nil
  elseif parsed.vault:match "^%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x%x$" then
    return ("Vault ID '%s' is not supported; use a configured workspace or vault name"):format(parsed.vault)
  else
    return ("Vault '%s' was not found in configured workspaces"):format(parsed.vault)
  end
end

--- Whether handling a URI can create or modify a file.
---
---@param parsed obsidian.uri.Parsed
---@return boolean
M.is_mutating = function(parsed)
  return parsed.action == "new"
    or parsed.action == "daily"
    or parsed.action == "unique"
    or (parsed.action == "open" and (parsed.append or parsed.prepend))
end

--- Dispatch a parsed URI.
---
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
M.dispatch = function(parsed)
  local handler = handlers[parsed.action]
  if not handler then
    return ut.failure(parsed, ("Unsupported action '%s'"):format(parsed.action))
  end
  if Obsidian == nil or not Obsidian.workspace then
    return ut.failure(parsed, "obsidian.nvim is not set up")
  end

  local workspace_error = resolve_workspace(parsed)
  if workspace_error then
    return ut.failure(parsed, workspace_error)
  end

  local ok, result = pcall(handler, parsed)
  if not ok then
    return ut.failure(parsed, tostring(result))
  end
  return result
end

--- Parse and handle an `obsidian://` URI.
---
---@param uri string
---@return obsidian.uri.Result
M.handle = function(uri)
  local parsed = M.parse(uri)
  if not parsed then
    local fallback = {
      action = "invalid",
      params = {},
      clipboard = false,
      silent = false,
      append = false,
      prepend = false,
      overwrite = false,
    }
    ---@cast fallback obsidian.uri.Parsed
    return ut.failure(fallback, "Not an obsidian:// URI")
  end
  return M.dispatch(parsed)
end

return M
