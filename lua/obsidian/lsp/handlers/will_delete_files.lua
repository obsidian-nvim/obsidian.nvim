---@param src string
---@param dest string
local function copy_dir(src, dest)
  vim.fn.mkdir(dest, "p")
  local handle = vim.uv.fs_scandir(src)
  if not handle then return end
  while true do
    local name, typ = vim.uv.fs_scandir_next(handle)
    if not name then break end
    local s = src .. "/" .. name
    local d = dest .. "/" .. name
    if typ == "directory" then
      copy_dir(s, d)
    else
      vim.uv.fs_copyfile(s, d)
    end
  end
end

return function(params, callback)
  if Obsidian.opts.files and Obsidian.opts.files.trash == "local" then
    local trash_dir = tostring(Obsidian.dir / ".trash")
    local vault_root = tostring(Obsidian.dir)

    for _, entry in ipairs(params.files) do
      local abs_path = vim.uri_to_fname(entry.uri)
      if not vim.startswith(abs_path, trash_dir) then
        local rel_path = abs_path:sub(#vault_root + 2) -- strip vault root + separator
        local dest = trash_dir .. "/" .. rel_path
        local stat = vim.uv.fs_stat(abs_path)

        if stat and stat.type == "directory" then
          copy_dir(abs_path, dest)
        else
          vim.fn.mkdir(vim.fs.dirname(dest), "p")
          vim.uv.fs_copyfile(abs_path, dest)
        end
      end
    end
  end

  callback(nil, {})
end
