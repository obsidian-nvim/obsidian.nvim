local api = require "obsidian.api"
local Path = require "obsidian.path"
local search = require "obsidian.search"
local util = require "obsidian.util"
local log = require "obsidian.log"
local attachment = require "obsidian.attachment"

---@param path? string|obsidian.Path
---@param opts { fragment: string|?, location: string|?, params: table<string, string>|?, query: string|? }|?
local function open_in_app(path, opts)
  opts = opts or {}
  local vault_name = vim.fs.basename(tostring(Obsidian.workspace.root))
  local open = Obsidian.opts.open.func or vim.ui.open
  if not path then
    return open("obsidian://open?vault=" .. vim.uri_encode(vault_name), opts)
  end
  path = tostring(path)
  local this_os = api.get_os()

  -- Normalize path for windows.
  if this_os == api.OSType.Windows then
    path = string.gsub(path, "/", "\\")
  end

  local encoded_vault = vim.uri_encode(vault_name)
  local encoded_path = vim.uri_encode(path)

  local uri
  if Obsidian.opts.open.use_advanced_uri then
    local line = vim.api.nvim_win_get_cursor(0)[1] or 1
    uri = ("obsidian://advanced-uri?vault=%s&filepath=%s&line=%i"):format(encoded_vault, encoded_path, line)
  else
    uri = ("obsidian://open?vault=%s&file=%s"):format(encoded_vault, encoded_path)
  end

  if opts.fragment and opts.fragment ~= "" then
    uri = uri .. "#" .. opts.fragment
  end

  open(uri, opts)
end

---@param data obsidian.CommandArgs
return function(data)
  ---@type string|?
  local search_term, path

  if data.args and data.args:len() > 0 then
    search_term = data.args
  else
    local link_string, _ = api.cursor_link()
    if link_string then
      local link_location = util.parse_link(link_string)
      if link_location and api.is_attachment_path(link_location) then
        search_term = link_location
      else
        search_term = util.parse_link(link_string, { strip = true }) -- TODO: jump to exact anchor/block
      end
    end
  end

  if search_term and vim.trim(search_term) ~= "" then
    if api.is_attachment_path(search_term) then
      local target = attachment.parse_link_target(search_term)
      local path = Path.new(api.resolve_attachment_path(search_term)):vault_relative_path()
      if not path then
        return log.err "Attachment is not inside the current vault"
      end
      return open_in_app(path, {
        fragment = target.fragment,
        location = search_term,
        params = target.params,
        query = target.query,
      })
    end

    search.resolve_note_async(search_term, function(notes)
      if vim.tbl_isempty(notes) then
        return log.err "Note under cursor is not resolved"
      end
      local note = notes[1]
      open_in_app(note.path:vault_relative_path())
    end)
  else
    -- Otherwise use the pathk of the current buffer.
    local bufname = vim.api.nvim_buf_get_name(0)
    path = Path.new(bufname):vault_relative_path()
    open_in_app(path)
  end
end
