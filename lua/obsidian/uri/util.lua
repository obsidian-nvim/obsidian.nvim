local log = require "obsidian.log"
local Path = require "obsidian.path"

local M = {}

---@class obsidian.uri.Result
---@field ok boolean
---@field action string
---@field interactive boolean
---@field silent boolean
---@field error string|?
---@field note obsidian.Note|?
---@field data table|?

--- Map a URI paneType to an obsidian.nvim open strategy.
--- `window` has no Neovim equivalent and falls back to the configured strategy.
---
---@param pane_type string|?
---@return obsidian.config.OpenStrategy|?
M.pane_type_to_open_strategy = function(pane_type)
  if not pane_type then
    return nil
  end

  local map = {
    tab = "tab",
    split = "hsplit",
  }
  local strategy = map[pane_type]
  if not strategy then
    log.warn("Unsupported paneType '%s', using configured open strategy", pane_type)
  end
  return strategy
end

---@param value string
---@return string
M.encode_component = function(value)
  return vim.uri_encode(value, "rfc2396")
end

---@param path string
---@return string
M.encode_path = function(path)
  path = path:gsub("\\", "/")
  local encoded = {}
  for part in path:gmatch "[^/]+" do
    encoded[#encoded + 1] = M.encode_component(part)
  end
  return table.concat(encoded, "/")
end

---@param base string
---@param params table<string, string>
---@return string
M.append_query = function(base, params)
  local values = {}
  for key, value in pairs(params) do
    values[#values + 1] = M.encode_component(key) .. "=" .. M.encode_component(value)
  end
  table.sort(values)
  if vim.tbl_isempty(values) then
    return base
  end
  local separator = base:find("?", 1, true) and "&" or "?"
  return base .. separator .. table.concat(values, "&")
end

---@param note obsidian.Note
---@return string
M.note_uri = function(note)
  local api = require "obsidian.api"
  local path = assert(note.path, "note path is required")
  local workspace = api.find_workspace(tostring(path)) or Obsidian.workspace
  local relative = path:relative_to(workspace.root)
  local vault = vim.fs.basename(tostring(workspace.root))
  return ("obsidian://open?vault=%s&file=%s"):format(M.encode_component(vault), M.encode_path(tostring(relative)))
end

---@param callback string
---@param params table<string, string>
local function open_callback(callback, params)
  vim.ui.open(M.append_query(callback, params))
end

---@param parsed obsidian.uri.Parsed
---@param fields { interactive: boolean|?, silent: boolean|?, note: obsidian.Note|?, data: table|? }|?
---@return obsidian.uri.Result
M.success = function(parsed, fields)
  fields = fields or {}
  local note = fields.note
  if parsed.x_success and note then
    local path = assert(note.path, "note path is required")
    open_callback(parsed.x_success, {
      name = path.stem,
      url = M.note_uri(note),
      file = vim.uri_from_fname(tostring(path)),
    })
  end
  return {
    ok = true,
    action = parsed.action,
    interactive = fields.interactive == true,
    silent = fields.silent == true,
    note = note,
    data = fields.data,
  }
end

---@param parsed obsidian.uri.Parsed
---@param message string
---@return obsidian.uri.Result
M.failure = function(parsed, message)
  log.err("Obsidian URI '%s' failed: %s", parsed.action, message)
  if parsed.x_error then
    open_callback(parsed.x_error, { errorMessage = message })
  end
  return {
    ok = false,
    action = parsed.action,
    interactive = false,
    silent = parsed.silent,
    error = message,
  }
end

---@param parsed obsidian.uri.Parsed
---@return string|?
M.content = function(parsed)
  if parsed.clipboard then
    local clipboard = vim.fn.getreg "+"
    if type(clipboard) == "string" and clipboard ~= "" then
      return clipboard
    end
  end
  return parsed.content
end

---@param content string
---@return string[]
local function content_lines(content)
  if content == "" then
    return {}
  end
  return vim.split(content, "\n", { plain = true })
end

--- Persist a URI note and apply content according to append/prepend/overwrite.
--- Existing frontmatter is preserved; incoming frontmatter is treated as content.
---
---@param note obsidian.Note
---@param parsed obsidian.uri.Parsed
---@param opts { content: string|?, force_append: boolean|?, create_with_template: boolean|? }|?
M.write_note = function(note, parsed, opts)
  opts = opts or {}
  local existed = note:exists()
  local content = opts.content
  local incoming = content ~= nil and content_lines(content) or nil

  -- A new `obsidian://new` note with content should contain exactly that
  -- content. Daily and unique handlers opt into their configured templates.
  if not existed and incoming and not opts.create_with_template then
    note:save {
      insert_frontmatter = false,
      update_content = function()
        return incoming
      end,
    }
    return
  elseif not existed then
    note:write()
  end

  if not incoming then
    return
  end

  local mode
  if opts.force_append or parsed.append or (not existed and not parsed.prepend and not parsed.overwrite) then
    -- New note content follows any configured template by default.
    mode = "append"
  elseif parsed.prepend then
    mode = "prepend"
  elseif parsed.overwrite then
    mode = "overwrite"
  else
    -- Existing files are unchanged unless a mutation mode is explicit.
    return
  end

  note:write {
    update_content = function(lines)
      if #lines == 1 and lines[1] == "" then
        lines = {}
      end
      if mode == "overwrite" then
        return incoming
      elseif mode == "prepend" then
        return vim.list_extend(vim.deepcopy(incoming), lines)
      else
        return vim.list_extend(lines, incoming)
      end
    end,
  }
end

---@param path obsidian.Path
---@param scope string
---@param template string|?
---@return obsidian.Note
M.note_at_path = function(path, scope, template)
  local Note = require "obsidian.note"
  if path:is_file() then
    return Note.from_file(path)
  end

  local note = Note.new(path.stem, {}, {}, path, path.stem)
  note.template = template
  Note._run_creation_lifecycle(note, scope)
  return note
end

---@param path obsidian.Path
---@return boolean
M.path_in_current_workspace = function(path)
  local root = Path.new(Obsidian.workspace.root):resolve()
  path = path:resolve()
  return path == root or root:is_parent_of(path)
end

return M
