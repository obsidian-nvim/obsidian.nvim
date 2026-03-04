local log = require "obsidian.log"

--- Handle the "hook-get-address" action (best-effort).
--- Copies the current note's obsidian:// URI to the clipboard.
---@param parsed obsidian.uri.Parsed
local function handle_hook_get_address(parsed)
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

return handle_hook_get_address
