local M = {}
local ns_id = vim.api.nvim_create_namespace "obsidian.footer"
local Note = require "obsidian.note"
local attached_bufs = {}
local timers = {}

-- HACK: for now before we have cache
vim.g.obsidian_footer_update_interval = 10000

vim.g.obsidian = "deprecated, use b:obsidian"

---@param buf integer
---@param footer_format string
---@param update_backlinks boolean|?
---@return string|?
local note_status = function(buf, footer_format, update_backlinks)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local note = Note.from_buffer(buf)
  if note == nil then
    return
  end
  local info = note:status(update_backlinks)
  if info == nil then
    return
  end
  local result = footer_format
  for k, v in pairs(info) do
    result = result:gsub("{{" .. k .. "}}", v)
  end
  return result
end

---@param buf integer
---@param update_backlinks boolean|?
local update_footer = vim.schedule_wrap(function(buf, update_backlinks)
  -- TODO: log in the future to a log file
  local _, _ = pcall(function()
    local footer_format = Obsidian.opts.footer.format
    ---@cast footer_format -nil
    local display_text = note_status(buf, footer_format, update_backlinks)
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

    if Obsidian.opts.statusline.enabled then
      local res = note_status(buf, Obsidian.opts.statusline.format, true)
      if res then
        vim.b[buf].obsidian_status = res
      end
    else
      vim.b[buf].obsidian_status = display_text
    end
  end)
end)

M.start = function(buf)
  local group = vim.api.nvim_create_augroup("obsidian.footer-" .. buf, {})
  if attached_bufs[buf] then
    return
  end
  local id = vim.api.nvim_create_autocmd({
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
  attached_bufs[buf] = id

  vim.api.nvim_create_autocmd({
    "BufWipeout",
    "BufUnload",
    "BufDelete",
  }, {
    group = group,
    buffer = buf,
    callback = function()
      local buf_timer = timers[buf]
      if buf_timer then
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
