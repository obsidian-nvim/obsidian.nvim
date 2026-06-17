local api = require "obsidian.api"
local Path = require "obsidian.path"
local search = require "obsidian.search"
local util = require "obsidian.util"
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

  if data.args and data.args:len() > 0 then
    search_term = data.args
  else
    local link_string, _ = api.cursor_link()
    if link_string then
      search_term = util.parse_link(link_string) -- TODO: jump to exact anchor/block
      if search_term then
        search_term = util.strip_anchor_links(search_term)
        search_term = util.strip_block_links(search_term)
      end
    end
  end

  if search_term and vim.trim(search_term) ~= "" then
    search.resolve_note_async(search_term, function(notes)
      if vim.tbl_isempty(notes) then
        return log.err "Note under cursor is not resolved"
      end
      local note = notes[1]
      ---@cast note -nil
      local path = note.path
      ---@cast path -nil
      open_in_app(path:vault_relative_path())
    end)
  else
    -- Otherwise use the pathk of the current buffer.
    local bufname = vim.api.nvim_buf_get_name(0)
    path = Path.new(bufname):vault_relative_path()
    open_in_app(path)
  end
end
