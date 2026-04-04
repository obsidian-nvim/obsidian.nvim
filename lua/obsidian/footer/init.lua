local M = {}
local ns_id = vim.api.nvim_create_namespace "obsidian.footer"
local Note = require "obsidian.note"
local Path = require "obsidian.path"
local attached_bufs = {}

---@type table<integer, uv.uv_timer_t>
local timers = {}

---@type table<string, obsidian.BacklinkMatch[]>
local linked_mentions_cache = {}

-- HACK: for now before we have cache
vim.g.obsidian_footer_update_interval = 10000

vim.g.obsidian = "deprecated, use b:obsidian"

---@param value string|string[]|number|nil
---@return string
local function substitution_to_string(value)
  if value == nil then
    return ""
  elseif type(value) == "table" then
    return table.concat(value, "\n")
  else
    return tostring(value)
  end
end

---@param text string
---@return string[]
local function split_lines(text)
  return vim.split(text, "\n", { plain = true })
end

---@param match obsidian.BacklinkMatch
---@return string, integer, integer, string
local function backlink_sort_key(match)
  local rel_path = Path.new(match.path):vault_relative_path() or tostring(match.path)
  return rel_path, match.line or 0, match.start or 0, match.text or ""
end

---@param matches obsidian.BacklinkMatch[]
---@return obsidian.BacklinkMatch[]
local function sort_backlink_matches(matches)
  table.sort(matches, function(a, b)
    local a_path, a_line, a_start, a_text = backlink_sort_key(a)
    local b_path, b_line, b_start, b_text = backlink_sort_key(b)

    if a_path ~= b_path then
      return a_path < b_path
    elseif a_line ~= b_line then
      return a_line < b_line
    elseif a_start ~= b_start then
      return a_start < b_start
    else
      return a_text < b_text
    end
  end)

  return matches
end

---@param note obsidian.Note
---@param update_backlinks boolean|?
---@return table<string, string|number|string[]|fun(note: obsidian.Note): string|string[]|number|nil>
local function build_substitutions(note, update_backlinks)
  ---@type { words: integer, chars: integer, properties: integer, backlinks: integer }?
  local status
  ---@type obsidian.BacklinkMatch[]?
  local backlink_matches

  local get_status = function()
    if status == nil then
      status = note:status(update_backlinks)
    end
    return status or {}
  end

  local get_backlink_matches = function()
    local path = tostring(note.path)
    if backlink_matches == nil then
      if update_backlinks or linked_mentions_cache[path] == nil then
        linked_mentions_cache[path] = sort_backlink_matches(note:backlinks {})
      end
      backlink_matches = linked_mentions_cache[path]
    end
    return backlink_matches
  end

  local builtins
  builtins = {
    words = function()
      return get_status().words or 0
    end,
    chars = function()
      return get_status().chars or 0
    end,
    properties = function()
      return get_status().properties or 0
    end,
    backlinks = function()
      return get_status().backlinks or 0
    end,
    status = function()
      local info = get_status()
      return string.format(
        "%d backlinks  %d properties  %d words  %d chars",
        info.backlinks or 0,
        info.properties or 0,
        info.words or 0,
        info.chars or 0
      )
    end,
    linked_mentions = function()
      local matches = get_backlink_matches()
      if #matches == 0 then
        return {}
      end

      local lines = { "Linked Mentions", "" }
      for _, match in ipairs(matches) do
        local rel_path = Path.new(match.path):vault_relative_path() or tostring(match.path)
        lines[#lines + 1] = string.format("%s: %s", rel_path, match.text or "")
      end

      return lines
    end,
    unlinked_mentions = function()
      return {}
    end,
  }

  local user_substitutions = Obsidian.opts.footer.substitutions or {}
  return vim.tbl_extend("force", builtins, user_substitutions)
end

---@param substitutions table<string, string|number|string[]|fun(note: obsidian.Note): string|string[]|number|nil>
---@param note obsidian.Note
---@param key string
---@return string|string[]|number|nil
local function evaluate_substitution(substitutions, note, key)
  local value = substitutions[key]
  if type(value) == "function" then
    return value(note)
  else
    return value
  end
end

---@param lines string[]
---@param substitutions table<string, string|number|string[]|fun(note: obsidian.Note): string|string[]|number|nil>
---@param note obsidian.Note
---@return string[]
local function apply_substitutions(lines, substitutions, note)
  local out = {}
  for _, line in ipairs(lines) do
    local exact_key = line:match "^{{%s*([%w_]+)%s*}}$"
    if exact_key ~= nil then
      local value = evaluate_substitution(substitutions, note, exact_key)
      if type(value) == "table" then
        for _, list_line in ipairs(value) do
          out[#out + 1] = tostring(list_line)
        end
      elseif value ~= nil then
        vim.list_extend(out, split_lines(tostring(value)))
      end
    else
      local rendered = line:gsub("{{%s*([%w_]+)%s*}}", function(key)
        local value = evaluate_substitution(substitutions, note, key)
        return substitution_to_string(value)
      end)
      vim.list_extend(out, split_lines(rendered))
    end
  end
  return out
end

---@param buf integer
---@param format string
---@param update_backlinks boolean|?
---@return string[]|?
local function render_lines(buf, format, update_backlinks)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local note = Note.from_buffer(buf)
  if note == nil then
    return
  end

  local substitutions = build_substitutions(note, update_backlinks)
  local lines = split_lines(format)
  return apply_substitutions(lines, substitutions, note)
end

---@param lines string[]|?
---@return string
local function flatten_lines(lines)
  if lines == nil then
    return ""
  end
  return table.concat(lines, "\n")
end

---@param buf integer
---@param update_backlinks boolean|?
local update_footer = vim.schedule_wrap(function(buf, update_backlinks)
  -- TODO: log in the future to a log file
  local _, _ = pcall(function()
    local footer_format = Obsidian.opts.footer.format
    ---@cast footer_format -nil
    local lines = render_lines(buf, footer_format, update_backlinks)
    if lines == nil then
      return
    end

    local row0 = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)
    local col0 = 0
    local separator = Obsidian.opts.footer.separator
    local hl_group = Obsidian.opts.footer.hl_group
    local footer_contents = vim.tbl_map(function(line)
      return { { line, hl_group } }
    end, lines)
    local footer_chunks
    if separator then
      local footer_separator = { { separator, hl_group } }
      footer_chunks = { footer_separator }
      vim.list_extend(footer_chunks, footer_contents)
    else
      footer_chunks = footer_contents
    end
    local opts = { virt_lines = footer_chunks }
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
    vim.api.nvim_buf_set_extmark(buf, ns_id, row0, col0, opts)

    if Obsidian.opts.statusline.enabled then
      local res = flatten_lines(render_lines(buf, Obsidian.opts.statusline.format, true))
      if res then
        vim.b[buf].obsidian_status = res
      end
    else
      vim.b[buf].obsidian_status = flatten_lines(lines)
    end
  end)
end)

M.start = function(buf)
  if attached_bufs[buf] then
    return
  end
  local group = vim.api.nvim_create_augroup("obsidian.footer-" .. buf, {})

  vim.api.nvim_create_autocmd({
    "FileChangedShellPost",
    "TextChanged",
    "TextChangedI",
    "TextChangedP",
  }, {
    group = group,
    desc = "Update obsidian footer",
    buffer = buf,
    callback = function()
      update_footer(buf)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_mode().mode:lower():find "v" then
        update_footer(buf)
      end
    end,
  })

  local timer = vim.uv:new_timer()
  assert(timer, "Failed to create timer")
  timer:start(0, vim.g.obsidian_footer_update_interval, function()
    update_footer(buf, true)
  end)

  timers[buf] = timer
  attached_bufs[buf] = true

  vim.api.nvim_create_autocmd({
    "BufWipeout",
    "BufUnload",
    "BufDelete",
  }, {
    group = group,
    buffer = buf,
    callback = function()
      local buf_path = vim.api.nvim_buf_get_name(buf)
      if buf_path ~= "" then
        linked_mentions_cache[Path.new(buf_path).filename] = nil
      end

      local buf_timer = timers[buf]
      if buf_timer ~= nil then
        buf_timer:stop()
        buf_timer:close()
        timers[buf] = nil
      end
      attached_bufs[buf] = nil
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

return M
