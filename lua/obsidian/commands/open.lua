local api = require "obsidian.api"
local Path = require "obsidian.path"
local search = require "obsidian.search"
local util = require "obsidian.util"
local link_resolver = require "obsidian.link"
local log = require "obsidian.log"

---@param path? string|obsidian.Path
local function open_in_app(path)
  local vault_name = vim.fs.basename(tostring(Obsidian.workspace.root))
  local open_func = Obsidian.opts.open.func
  ---@cast open_func -nil
  if not path then
    return open_func("obsidian://open?vault=" .. vim.uri_encode(vault_name))
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

  open_func(uri)
end

---@param data obsidian.CommandArgs
return function(data)
  ---@type string|?
  local search_term, path
  local from_cursor_link = false
  local cursor_link_type

  if data.args and data.args:len() > 0 then
    search_term = data.args
  else
    local link_string
    link_string, cursor_link_type = api.cursor_link()
    if link_string then
      from_cursor_link = true
      search_term = util.parse_link(link_string) -- TODO: jump to exact anchor/block
      if search_term then
        search_term = util.strip_anchor_links(search_term)
        search_term = util.strip_block_links(search_term)
      end
    end
  end

  if search_term and vim.trim(search_term) ~= "" then
    local function open_note(note)
      if not note then
        return log.err "Note under cursor is not resolved"
      end
      local note_path = note.path
      ---@cast note_path -nil
      open_in_app(note_path:vault_relative_path())
    end

    if from_cursor_link and (cursor_link_type == "wiki" or cursor_link_type == "markdown") then
      ---@cast cursor_link_type "wiki"|"markdown"
      link_resolver.resolve_async(search_term, function(result)
        local notes = result.notes or {}
        open_note(result.status == "resolved" and #notes == 1 and notes[1] or nil)
      end, { source_path = vim.api.nvim_buf_get_name(0), link_type = cursor_link_type })
    else
      -- Free-form command arguments intentionally keep fuzzy search behavior.
      search.resolve_note_async(search_term, function(notes)
        open_note(notes[1])
      end)
    end
  else
    -- Otherwise use the pathk of the current buffer.
    local bufname = vim.api.nvim_buf_get_name(0)
    path = Path.new(bufname):vault_relative_path()
    open_in_app(path)
  end
end
