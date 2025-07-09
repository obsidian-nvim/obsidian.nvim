local api = require "obsidian.api"
local Path = require "obsidian.path"
local search = require "obsidian.search"
local log = require "obsidian.log"

---@param path? string|obsidian.Path
local function open_in_app(path)
  local vault_name = vim.fs.basename(tostring(Obsidian.workspace.root))
  if not path then
    return Obsidian.opts.open.func("obsidian://open?vault=" .. vim.uri_encode(vault_name))
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
  print(uri)

  Obsidian.opts.open.func(uri)
end

---@param data CommandArgs
return function(_, data)
  ---@type string|?
  local search_term

  if data.args and data.args:len() > 0 then
    search_term = data.args
  else
    -- Check for a note reference under the cursor.
    local link_string, _ = api.cursor_link()
    search_term = link_string
  end

  if search_term then
    search.resolve_link_async(search_term, function(results)
      if vim.tbl_isempty(results) then
        return log.err "Note under cusros is not resolved"
      end
      vim.schedule(function()
        open_in_app(results[1].path)
      end)
    end)
  else
    -- Otherwise use the path of the current buffer.
    local bufname = vim.api.nvim_buf_get_name(0)
    local path = Path.new(bufname):vault_relative_path()
    open_in_app(path)
  end
end
