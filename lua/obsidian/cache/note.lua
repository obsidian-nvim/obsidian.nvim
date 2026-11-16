local parse_note = require "obsidian.parse.note"

local M = {}

---Convert a file to a cache note row. Invalid files must not retain stale data.
---@param abs_path string
---@param _vault_root string
---@return table? row
function M.build(abs_path, _vault_root)
  local stat = vim.uv.fs_stat(abs_path)
  if not stat or stat.type ~= "file" then
    return nil
  end
  local ok, row = pcall(parse_note.from_file, abs_path)
  if not ok then
    return nil
  end
  row.stat = {
    mtime_sec = stat.mtime.sec,
    mtime_nsec = stat.mtime.nsec,
    size = stat.size,
  }
  return row
end

return M
