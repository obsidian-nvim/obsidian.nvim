local Path = require "obsidian.path"
local log = require "obsidian.log"

local M = {}

local function char_to_hex(c)
  return string.format("%%%02X", string.byte(c))
end

--- Encode a string for use in a URL.
---@param str string
---@param opts? { keep_path_sep?: boolean }
---@return string
M.encode = function(str, opts)
  opts = opts or {}
  local url = str:gsub("\n", "\r\n")
  url = url:gsub("([%(%)%*%?%[%]%$\"':<>|\\'{}&])", char_to_hex)
  if not opts.keep_path_sep then
    url = url:gsub("/", char_to_hex)
  end
  url = url:gsub(" ", "%%20")
  return url
end

--- Return a URI's normalized scheme. Windows drive paths are not URIs.
---@param value string
---@return string? scheme
M.scheme = function(value)
  local scheme, rest = value:match "^([%a][%w+%-%.]*):(.*)$"
  if not scheme or not rest then
    return nil
  end
  if #scheme == 1 and rest:match "^[\\/]." then
    return nil
  end
  return scheme:lower()
end

---@param value string
---@return boolean is_uri
---@return string? scheme
M.is_uri = function(value)
  local scheme = M.scheme(value)
  return scheme ~= nil, scheme
end

local known_actions = {
  open = true,
  new = true,
  daily = true,
  unique = true,
  search = true,
  ["choose-vault"] = true,
}

---@class obsidian.uri.Operation
---@field note obsidian.Note|?
---@field interactive boolean|?
---@field data table|?

---@class obsidian.uri.Result: obsidian.uri.Operation
---@field ok boolean
---@field action string
---@field interactive boolean
---@field silent boolean
---@field error string|?

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
  local hash_pos = value:find("#", 1, true)
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
---@field heading string|?
---@field spacing string|? Validated during dispatch: auto, newline, or inline.
---@field anchor string|?
---@field clipboard boolean
---@field silent boolean
---@field append boolean
---@field prepend boolean
---@field overwrite boolean
---@field pane_type string|?

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
      local shorthand = rest:gsub("^vault/", "")
      local decoded = vim.uri_decode(shorthand)
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
    anchor = path_anchor
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
    heading = params.heading,
    spacing = params.spacing,
    anchor = anchor,
    clipboard = params.clipboard ~= nil,
    silent = params.silent ~= nil,
    append = params.append ~= nil,
    prepend = params.prepend ~= nil,
    overwrite = params.overwrite ~= nil,
    pane_type = params.paneType,
  }
end

---@param workspace obsidian.Workspace
local function set_workspace(workspace)
  if Obsidian.workspace ~= workspace then
    require("obsidian.workspace").set(workspace)
  end
end

---@param parsed obsidian.uri.Parsed
---@return string|?
local function resolve_workspace(parsed)
  -- `path` overrides `vault` and `file` in the Obsidian URI contract.
  if parsed.path then
    if not Path.new(parsed.path):is_absolute() then
      return "The path parameter must be absolute"
    end
    local workspace = require("obsidian.api").find_workspace(parsed.path)
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
    or (parsed.action == "open" and (parsed.append or parsed.prepend or parsed.overwrite))
end

--- Resolve URI target precedence and enforce workspace confinement before creation callbacks.
---@param parsed obsidian.uri.Parsed
---@return obsidian.Path|?
local function resolve_target(parsed)
  if parsed.action ~= "new" and parsed.action ~= "open" then
    return nil
  end

  local path
  if parsed.path then
    path = Path.new(parsed.path):resolve()
  elseif parsed.file then
    path = (Obsidian.workspace.root / parsed.file):resolve()
    if parsed.action == "open" then
      local markdown = (Obsidian.workspace.root / (parsed.file .. ".md")):resolve()
      if markdown:is_file() then
        path = markdown
      end
    end
  elseif parsed.action == "new" then
    path = require("obsidian.note").resolve_path {
      id = parsed.name,
      verbatim = parsed.name ~= nil,
      template = Obsidian.opts.note.template,
    }
  else
    return nil
  end

  if parsed.file and parsed.action == "new" then
    path = path:with_suffix(".md", true)
  elseif path.suffix == nil then
    local markdown = path:with_suffix ".md"
    if not path:is_file() then
      path = markdown
    end
  end
  path = path:resolve()
  local root = Obsidian.workspace.root:resolve()
  if path ~= root and not root:is_parent_of(path) then
    error(("File escapes the selected workspace: %s"):format(path), 0)
  end
  return path
end

--- Dispatch a parsed URI. Handlers resolve operations; this boundary owns URI
--- content/opening policy and results. External callbacks are not executed.
---@param parsed obsidian.uri.Parsed
---@return obsidian.uri.Result
M.dispatch = function(parsed)
  local ok, operation = pcall(function()
    if not known_actions[parsed.action] then
      error(("Unsupported action '%s'"):format(parsed.action), 0)
    end
    if Obsidian == nil or not Obsidian.workspace then
      error("obsidian.nvim is not set up", 0)
    end

    -- Do not mutate the caller's parsed request when applying protocol defaults.
    parsed = vim.deepcopy(parsed)
    if parsed.heading and (parsed.action == "new" or parsed.action == "daily") and not parsed.prepend then
      parsed.append = true
    end
    if parsed.heading ~= nil or parsed.spacing ~= nil then
      if not parsed.append and not parsed.prepend then
        error("The heading and spacing URI parameters require append or prepend", 0)
      end
      if parsed.spacing and not vim.list_contains({ "auto", "newline", "inline" }, parsed.spacing) then
        error(("Unsupported spacing '%s'"):format(parsed.spacing), 0)
      end
    end

    local workspace_error = resolve_workspace(parsed)
    if workspace_error then
      error(workspace_error, 0)
    end
    if parsed.clipboard then
      local clipboard = vim.fn.getreg "+"
      if type(clipboard) == "string" and clipboard ~= "" then
        parsed.content = clipboard
      end
    end
    ---@type fun(parsed: obsidian.uri.Parsed, path: obsidian.Path|?): obsidian.uri.Operation
    local handler = require("obsidian.uri.handlers." .. parsed.action)
    local resolved = handler(parsed, resolve_target(parsed))
    local note = resolved.note
    if note then
      local existed = note:exists()
      local content = parsed.content
      if not existed then
        if parsed.action == "new" and content ~= nil and not parsed.heading then
          note:save { content = content, insert_frontmatter = false }
          content = nil
        else
          note = note:write()
          resolved.note = note
        end
      end

      if content ~= nil then
        if parsed.append or parsed.prepend or parsed.action == "unique" or (not existed and not parsed.overwrite) then
          local spacing = parsed.spacing or "auto"
          ---@cast spacing "auto"|"newline"|"inline"
          note:insert_text(content, {
            target = parsed.heading and "section" or "body",
            section = parsed.heading and (vim.trim(parsed.heading):gsub("^#+%s*", "")) or nil,
            ignore_case = true,
            include_children = true,
            placement = parsed.prepend and not parsed.append and "top" or "bot",
            spacing = spacing,
            on_section_missing = "error",
            insert_frontmatter = false,
          })
        elseif parsed.overwrite then
          note:save { content = content, insert_frontmatter = false }
        end
      end
      if not parsed.silent or parsed.action == "open" or parsed.action == "unique" then
        note:open {
          sync = true,
          anchor = parsed.anchor and not vim.startswith(parsed.anchor, "#^") and parsed.anchor or nil,
          block = parsed.anchor and vim.startswith(parsed.anchor, "#^") and parsed.anchor:sub(3) or nil,
          open_strategy = ({ tab = "tab", split = "hsplit" })[parsed.pane_type],
        }
        if parsed.pane_type and parsed.pane_type ~= "tab" and parsed.pane_type ~= "split" then
          log.warn("Unsupported paneType '%s', using configured open strategy", parsed.pane_type)
        end
      end
    end
    return resolved
  end)

  ---@type obsidian.uri.Result
  local result = {
    ok = ok,
    action = parsed.action,
    interactive = ok and operation.interactive == true,
    silent = parsed.silent and (not ok or parsed.action == "new" or parsed.action == "daily"),
    note = ok and operation.note or nil,
    data = ok and operation.data or nil,
    error = not ok and tostring(operation) or nil,
  }
  if not ok then
    log.err("Obsidian URI '%s' failed: %s", parsed.action, result.error)
  end

  return result
end

--- Parse and handle an obsidian:// URI.
---@param uri string
---@return obsidian.uri.Result
M.handle = function(uri)
  local parsed = M.parse(uri)
  if not parsed then
    return {
      ok = false,
      action = "invalid",
      interactive = false,
      silent = false,
      error = "Not an obsidian:// URI",
    }
  end
  return M.dispatch(parsed)
end

return M
