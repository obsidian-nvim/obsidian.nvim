local M = {}
local ns_id = vim.api.nvim_create_namespace "obsidian.footer"
local Note = require "obsidian.note"
local watchfiles = require "obsidian.lsp.watchfiles"

---@class obsidian.footer.State
---@field backlinks integer?
---@field unregister fun()

---@type table<integer, obsidian.footer.State>
local attached_bufs = {}

vim.g.obsidian = "deprecated, use b:obsidian"

---@param format string
---@param info { words: integer, chars: integer, properties: integer, backlinks: integer }
---@return string
local function format_status(format, info)
  for k, v in pairs(info) do
    format = format:gsub("{{" .. k .. "}}", v)
  end
  return format
end

---@return boolean
local function needs_backlinks()
  local footer_format = Obsidian.opts.footer.format
  local statusline_format = Obsidian.opts.statusline.format
  local footer_has_backlinks = footer_format ~= nil and footer_format:find("{{backlinks}}", 1, true) ~= nil
  local statusline_has_backlinks = Obsidian.opts.statusline.enabled == true
    and statusline_format ~= nil
    and statusline_format:find("{{backlinks}}", 1, true) ~= nil
  return footer_has_backlinks or statusline_has_backlinks
end

---@param buf integer
---@param update_backlinks boolean
---@param callback fun(info: { words: integer, chars: integer, properties: integer, backlinks: integer }|?)
local function note_status(buf, update_backlinks, callback)
  if not vim.api.nvim_buf_is_valid(buf) then
    return callback(nil)
  end
  local note = Note.from_buffer(buf)
  if note == nil then
    return callback(nil)
  end
  note:status(update_backlinks, function(info)
    local state = attached_bufs[buf]
    if not state then
      return callback(nil)
    end
    if info.backlinks ~= nil then
      state.backlinks = info.backlinks
    end
    callback {
      words = info.words,
      chars = info.chars,
      properties = info.properties,
      backlinks = state.backlinks or 0,
    }
  end)
end

---@param buf integer
---@param display_text string
local function render_footer(buf, display_text)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local row0 = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)
  local col0 = 0
  local separator = Obsidian.opts.footer.separator
  local hl_group = Obsidian.opts.footer.hl_group
  local footer_contents = { { display_text, hl_group } }
  local footer_chunks
  if separator then
    local footer_separator = { { separator, hl_group } }
    footer_chunks = { footer_separator, footer_contents }
  else
    footer_chunks = { footer_contents }
  end
  local opts = { virt_lines = footer_chunks }
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  vim.api.nvim_buf_set_extmark(buf, ns_id, row0, col0, opts)
end

---@param buf integer
---@param update_backlinks boolean
local update_footer = vim.schedule_wrap(function(buf, update_backlinks)
  pcall(function()
    note_status(buf, update_backlinks, function(info)
      pcall(function()
        if not info or not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        local footer_format = Obsidian.opts.footer.format
        ---@cast footer_format -nil
        render_footer(buf, format_status(footer_format, info))

        local statusline_format = Obsidian.opts.statusline.format
        if Obsidian.opts.statusline.enabled and statusline_format then
          vim.b[buf].obsidian_status = format_status(statusline_format, info)
        else
          vim.b[buf].obsidian_status = format_status(footer_format, info)
        end
      end)
    end)
  end)
end)

---@param event table
---@param buf_path string
---@return boolean
local function is_current_file(event, buf_path)
  for _, key in ipairs { "path", "old_path", "new_path" } do
    if event[key] and vim.fs.normalize(event[key]) == buf_path then
      return true
    end
  end
  return false
end

M.start = function(buf)
  if attached_bufs[buf] then
    return
  end
  local group = vim.api.nvim_create_augroup("obsidian.footer-" .. buf, {})
  local state = {
    unregister = function() end,
  }
  attached_bufs[buf] = state

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
      update_footer(buf, false)
    end,
  })
  vim.api.nvim_create_autocmd("CursorMoved", {
    group = group,
    buffer = buf,
    callback = function()
      if vim.api.nvim_get_mode().mode:lower():find "v" then
        update_footer(buf, false)
      end
    end,
  })

  state.unregister = watchfiles.register_handler(function(events)
    if not needs_backlinks() or not vim.api.nvim_buf_is_valid(buf) then
      return
    end
    local buf_path = vim.fs.normalize(vim.api.nvim_buf_get_name(buf))
    for _, event in ipairs(events) do
      if not is_current_file(event, buf_path) then
        update_footer(buf, true)
        return
      end
    end
  end)

  update_footer(buf, needs_backlinks())

  vim.api.nvim_create_autocmd({
    "BufWipeout",
    "BufUnload",
    "BufDelete",
  }, {
    group = group,
    buffer = buf,
    callback = function()
      local buf_state = attached_bufs[buf]
      if buf_state then
        buf_state.unregister()
        attached_bufs[buf] = nil
      end
      pcall(vim.api.nvim_del_augroup_by_id, group)
    end,
  })
end

return M
