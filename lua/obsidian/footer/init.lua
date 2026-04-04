local M = {}
local ns_id = vim.api.nvim_create_namespace "obsidian.footer"
local Note = require "obsidian.note"
local attached_bufs = {}

---@type table<integer, uv.uv_timer_t>
local timers = {}

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

local builtins = {
  words = function()
    local wc = vim.fn.wordcount()
    return wc.visual_words or wc.words or 0
  end,
  chars = function()
    local wc = vim.fn.wordcount()
    return wc.visual_chars or wc.chars or 0
  end,
  properties = function(note)
    return vim.tbl_count(note:frontmatter()) -- TODO: should be zero if no frontmatter
  end,
  backlinks = function(note, update)
    return note:status(update).backlinks or 0
  end,
  status = function(note, update)
    local info = note:status(update) or {}
    return string.format(
      "%d backlinks  %d properties  %d words  %d chars",
      info.backlinks or 0,
      info.properties or 0,
      info.words or 0,
      info.chars or 0
    )
  end,
}

---@param substitutions table<string, string|number|string[]|fun(note: obsidian.Note, update: boolean): string|string[]|number|nil>
---@param note obsidian.Note
---@param key string
---@param update boolean
---@return string|string[]|number|nil
local function evaluate_substitution(substitutions, note, key, update)
  local value = substitutions[key]
  if type(value) == "function" then
    return value(note, update)
  else
    return value
  end
end

---@param lines string[]
---@param substitutions table<string, string|number|string[]|fun(note: obsidian.Note): string|string[]|number|nil>
---@param note obsidian.Note
---@return string[]
local function apply_substitutions(lines, substitutions, note, trigger_update)
  local out = {}
  for _, line in ipairs(lines) do
    local exact_key = line:match "^{{%s*([%w_]+)%s*}}$"
    if exact_key ~= nil then
      local value = evaluate_substitution(substitutions, note, exact_key, trigger_update)
      if type(value) == "table" then
        for _, list_line in ipairs(value) do
          out[#out + 1] = tostring(list_line)
        end
      elseif value ~= nil then
        vim.list_extend(out, split_lines(tostring(value)))
      end
    else
      local rendered = line:gsub("{{%s*([%w_]+)%s*}}", function(key)
        local value = evaluate_substitution(substitutions, note, key, trigger_update)
        return substitution_to_string(value)
      end)
      vim.list_extend(out, split_lines(rendered))
    end
  end
  return out
end

---@param buf integer
---@param format string
---@param trigger_update boolean|?
---@return string[]|?
local function render_lines(buf, format, trigger_update)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local note = Note.from_buffer(buf)
  if note == nil then
    return
  end

  local user_substitutions = Obsidian.opts.footer.substitutions or {}
  local substitutions = vim.tbl_extend("force", builtins, user_substitutions)

  local lines = split_lines(format)
  return apply_substitutions(lines, substitutions, note, trigger_update)
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
