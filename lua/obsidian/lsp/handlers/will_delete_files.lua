local api = require "obsidian.api"
local Note = require "obsidian.note"
local util = require "obsidian.util"
local attachment = require "obsidian.attachment"
local search = require "obsidian.search"

--- Copy a directory tree.
---@param src string
---@param dest string
local function copy_dir(src, dest)
  vim.fn.mkdir(dest, "p")
  local handle = vim.uv.fs_scandir(src)
  if not handle then
    return
  end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then
      break
    end
    local s = src .. "/" .. name
    local d = dest .. "/" .. name
    if typ == "directory" then
      copy_dir(s, d)
    else
      vim.uv.fs_copyfile(s, d)
    end
  end
end

--- Trash (copy to .trash) a single file or directory. Returns the trash path.
---@param abs_path string
---@param trash_dir string
---@param vault_root string
---@return string|?
local function trash_file(abs_path, trash_dir, vault_root)
  local rel_path = abs_path:sub(#vault_root + 2)
  local dest = trash_dir .. "/" .. rel_path
  local stat = vim.uv.fs_stat(abs_path)
  if not stat then
    return nil
  end
  if stat.type == "directory" then
    copy_dir(abs_path, dest)
  else
    vim.fn.mkdir(vim.fs.dirname(dest), "p")
    vim.uv.fs_copyfile(abs_path, dest)
  end
  return dest
end

--- Prompt the user about backlinks for the file at `abs_path`.
--- Always fires when backlinks are found. Returns whether the user confirmed.
--- The actual deletion still happens regardless via the LSP client.
---
---@param abs_path string
---@param basename string|?
---@return boolean true if no backlinks or user confirmed
local function check_backlinks(abs_path, basename)
  local matches
  basename = basename or vim.fs.basename(abs_path)

  if vim.endswith(abs_path, ".md") then
    local ok, note = pcall(Note.from_file, abs_path)
    if not ok or not note then
      return true
    end
    matches = note:backlinks()
  else
    local vault_root = tostring(Obsidian.dir)
    local rel_path = abs_path:sub(#vault_root + 2)
    matches = search.find_backlinks(nil, {
      refs = { basename, rel_path },
      dir = Obsidian.dir,
      timeout = 2000,
    })
  end

  if matches and #matches > 0 then
    local prompt = ("'%s' is referenced in %d place(s). Delete anyway?"):format(basename, #matches)
    return api.confirm(prompt) == "Yes"
  end

  return true
end

--- For a note being deleted, find attachment links and prompt the user to
--- also delete each one. Attachments are NOT in params.files so the client
--- won't touch them — if the user confirms, we trash (if enabled) and delete
--- the original ourselves.
---
---@param abs_path string Note being deleted.
---@param trash_dir string|? nil if trash is disabled.
---@param vault_root string
local function check_attachment_links(abs_path, trash_dir, vault_root)
  if not vim.endswith(abs_path, ".md") then
    return
  end

  local ok, note = pcall(Note.from_file, abs_path)
  if not ok or not note then
    return
  end

  local links = note:links()

  for _, link in ipairs(links) do
    local loc = assert(util.parse_link(link.link), "")
    if attachment.is_attachment_path(loc) then
      local resolved = attachment.resolve_attachment_path(loc, tostring(note.path))
      if resolved then
        local prompt = ("Note contains attachment '%s'. Delete it too?"):format(vim.fs.basename(resolved))
        if api.confirm(prompt) == "Yes" then
          -- Client won't delete this, we have to do it.
          if trash_dir then
            trash_file(resolved, trash_dir, vault_root)
          end
          local del_stat = vim.uv.fs_stat(resolved)
          vim.fn.delete(resolved, del_stat and del_stat.type == "directory" and "rf" or "")
        end
      end
    end
  end
end

---@param params lsp.DeleteFilesParams
---@param callback function
return function(params, callback)
  if not params or not params.files then
    return callback(nil, {})
  end

  local trash_dir
  if Obsidian.opts.file and Obsidian.opts.file.trash == "local" then
    trash_dir = tostring(Obsidian.dir / ".trash")
  end
  local vault_root = tostring(Obsidian.dir)

  for _, entry in ipairs(params.files) do
    local abs_path = vim.uri_to_fname(entry.uri)
    if vim.startswith(abs_path, vault_root) then
      -- Prompt about backlinks (always — regardless of trash setting).
      local confirmed = check_backlinks(abs_path)
      if confirmed then
        -- Copy to .trash if enabled.
        if trash_dir and not vim.startswith(abs_path, trash_dir) then
          trash_file(abs_path, trash_dir, vault_root)
        end

        -- Check for attachment links inside notes.
        check_attachment_links(abs_path, trash_dir, vault_root)
      end
    end
  end

  callback(nil, {})
end
