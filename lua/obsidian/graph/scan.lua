local filetypes = require "obsidian.filetypes"
local fs = require "obsidian.fs"
local parse_note = require "obsidian.parse.note"

local M = {}

---Scan the same inventory as the metadata cache, without enabling that cache.
---Ripgrep enumerates files, not matching lines: isolated notes must survive.
---@param vault string
---@param opts { config_dir: string, ignore_checker: obsidian.lib.Glob? }
---@param callback fun(rows: table<string, table>?, err: string?)
---@return fun() cancel
function M.scan(vault, opts, callback)
  local cancelled = false
  local cancel_scan

  local function in_scope(path)
    local rel = path:sub(#vault + 2):gsub("\\", "/")
    local first = rel:match "^[^/]+"
    return filetypes.kind(path) ~= nil
      and first ~= ".git"
      and first ~= opts.config_dir
      and (not opts.ignore_checker or not opts.ignore_checker:check(rel))
  end

  local function load(paths)
    local rows = {}
    local i = 1
    local function step()
      if cancelled then
        return
      end
      -- Yield between batches rather than parse the whole vault in one turn.
      for _ = 1, 20 do
        local path = paths[i]
        if not path then
          callback(rows)
          return
        end
        i = i + 1
        path = vim.fs.normalize(path)
        if in_scope(path) then
          local stat = vim.uv.fs_stat(path)
          if not stat or stat.type ~= "file" then
            callback(nil, "graph: file disappeared during scan: " .. path)
            return
          end
          if filetypes.is_note(path) then
            local ok, row = pcall(parse_note.from_file, path)
            if not ok then
              callback(nil, "graph: could not parse " .. path .. ": " .. tostring(row))
              return
            end
            rows[path] = row
          else
            rows[path] = { kind = "attachment" }
          end
        end
      end
      vim.schedule(step)
    end
    vim.schedule(step)
  end

  if vim.fn.executable "rg" == 1 then
    -- Cache inventory includes hidden/gitignored files. Apply its configured
    -- ignore checker below instead of rg globs, whose semantics differ.
    local ok, handle = pcall(vim.system, {
      "rg",
      "--no-config",
      "--files",
      "--hidden",
      "--no-ignore",
      "--null",
      vault,
    }, {}, function(result)
      vim.schedule(function()
        if cancelled then
          return
        end
        if result.code ~= 0 and not (result.code == 1 and (result.stderr or "") == "") then
          callback(nil, "graph: rg inventory failed: " .. (result.stderr or tostring(result.code)))
          return
        end
        load(vim.split(result.stdout or "", "\0", { plain = true, trimempty = true }))
      end)
    end)
    if ok then
      cancel_scan = function()
        handle:kill(15)
      end
    else
      vim.schedule(function()
        if not cancelled then
          callback(nil, "graph: rg inventory failed: " .. tostring(handle))
        end
      end)
    end
  else
    cancel_scan = fs.find_files_async(vault, {
      hidden = true,
      gitignore = false,
      ignore = false,
      sort_by = false,
      predicate = in_scope,
      prune = function(path)
        local rel = path:sub(#vault + 2)
        return rel == ".git" or rel == opts.config_dir
      end,
    }, load)
  end

  return function()
    cancelled = true
    if cancel_scan then
      cancel_scan()
    end
  end
end

return M
