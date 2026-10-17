local api = require "obsidian.api"
local icons = require "obsidian.icons"
local log = require "obsidian.log"
local Path = require "obsidian.path"
local picker = require "obsidian.picker"
local picker_util = require "obsidian.picker.util"
local search = require "obsidian.search"
local util = require "obsidian.interfaces.util"
local preview = require "obsidian.preview"

local M = {}

local function preview_cached_entry(entry)
  local data = entry.user_data or {}
  if not data.missing then
    return preview.path(entry.filename)
  end

  local cache = require "obsidian.cache"
  local references = vim.deepcopy(data.references or {})
  table.sort(references, function(a, b)
    local a_path, b_path = cache.notes.rel_path(a.filename), cache.notes.rel_path(b.filename)
    if a_path ~= b_path then
      return a_path < b_path
    elseif a.lnum ~= b.lnum then
      return a.lnum < b.lnum
    else
      return a.col < b.col
    end
  end)

  local lines = {}
  for i, reference in ipairs(references) do
    if i > 1 then
      lines[#lines + 1] = ""
    end
    lines[#lines + 1] = ("%s:%d:%d"):format(cache.notes.rel_path(reference.filename), reference.lnum, reference.col)
    lines[#lines + 1] = ""
    lines[#lines + 1] = "```markdown"
    lines[#lines + 1] = reference.raw
    lines[#lines + 1] = "```"
  end
  return preview.text(lines, "markdown")
end

---@param opts obsidian.PickerFindOpts|?
---@return boolean handled
M.find_files = function(opts)
  opts = opts or {}
  local context = util.capture_context { workspace_dir = opts.dir and tostring(opts.dir) or nil }
  picker.state.calling_bufnr = context.bufnr

  local selection_mappings = {}
  if not opts.no_default_mappings then
    selection_mappings["<C-q>"] = picker_util.send_to_qf_mapping {
      title = opts.prompt_title or "Files",
      strings_are_paths = true,
    }
  end
  for lhs, mapping in pairs(opts.selection_mappings or {}) do
    if mapping == false then
      selection_mappings[lhs] = nil
    else
      selection_mappings[lhs] = mapping
    end
  end

  local function present(values, dir, query, cached)
    if #values == 0 then
      return log.info "No matching files"
    end
    local pick_opts = {
      prompt = opts.prompt_title,
      allow_multiple = opts.allow_multiple ~= false,
      query = query,
      query_mappings = opts.query_mappings,
      selection_mappings = selection_mappings,
    }
    if cached then
      pick_opts.preview_item = preview_cached_entry
    else
      pick_opts.format_item = function(path)
        return icons.get_path_icon(path) .. " " .. tostring(Path.new(path):relative_to(dir))
      end
      pick_opts.preview_item = picker_util.preview_path
    end

    util.select(values, pick_opts, nil, function(items)
      if opts.callback then
        local paths = vim.tbl_map(function(item)
          return cached and item.filename or item
        end, items)
        opts.callback(paths)
      elseif cached then
        require("obsidian.actions")._open_cached_file_choices(items, { bufnr = context.bufnr })
      else
        picker_util.open_notes(items, {
          strings_are_paths = true,
          title = opts.prompt_title or "Files",
        })
      end
    end)
  end

  local cache = require "obsidian.cache"
  if
    cache.find_files_data(opts, function(candidates, query)
      local entries = vim.tbl_map(function(candidate)
        return {
          text = candidate.label,
          filename = candidate.path,
          user_data = {
            attachment = candidate.attachment,
            missing = candidate.missing,
            references = candidate.references,
            target = candidate.target,
          },
        }
      end, candidates)
      present(entries, opts.dir or api.resolve_workspace_dir(), query, true)
    end)
  then
    return true
  end

  local dir = Path.new(opts.dir or context.workspace_dir or api.resolve_workspace_dir()):resolve { strict = true }
  local paths = {}
  search.find_async(dir, nil, {
    sort_by = Obsidian.opts.search.sort_by,
    sort_reversed = Obsidian.opts.search.sort_reversed,
    include_non_markdown = opts.include_non_markdown,
  }, function(path)
    paths[#paths + 1] = path
  end, function(code)
    if code ~= 0 then
      return log.err("Failed to enumerate files in '%s'", dir)
    end
    present(paths, dir, opts.query, false)
  end)
  return true
end

return M
