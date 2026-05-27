local M = {}
local ns_id = vim.api.nvim_create_namespace "obsidian.footer"
local Note = require "obsidian.note"
local attached_bufs = {}

---@type table<integer, uv.uv_timer_t>
local timers = {}

-- HACK: for now before we have cache
vim.g.obsidian_footer_update_interval = 10000

vim.g.obsidian = "deprecated, use b:obsidian"

---@param buf integer
---@param footer_format string
---@param update_backlinks boolean|?
---@param callback fun(result: string|?)
local note_status = function(buf, footer_format, update_backlinks, callback)
  if not vim.api.nvim_buf_is_valid(buf) then
    return callback(nil)
  end
  local note = Note.from_buffer(buf)
  if note == nil then
    return callback(nil)
  end
  note:status(update_backlinks, function(info)
    if info == nil then
      return callback(nil)
    end
    local result = footer_format
    for k, v in pairs(info) do
      result = result:gsub("{{" .. k .. "}}", v)
    end
    callback(result)
  end)
end

---@param buf integer
---@param display_text string|?
local render_footer = function(buf, display_text)
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
---@param update_backlinks boolean|?
local update_footer = vim.schedule_wrap(function(buf, update_backlinks)
  -- TODO: log in the future to a log file
  pcall(function()
    local footer_format = Obsidian.opts.footer.format
    ---@cast footer_format -nil
    note_status(buf, footer_format, update_backlinks, function(display_text)
      pcall(function()
        if not vim.api.nvim_buf_is_valid(buf) then
          return
        end

        render_footer(buf, display_text)

        if Obsidian.opts.statusline.enabled then
          note_status(buf, Obsidian.opts.statusline.format, true, function(res)
            pcall(function()
              if res and vim.api.nvim_buf_is_valid(buf) then
                vim.b[buf].obsidian_status = res
              end
            end)
          end)
        else
          vim.b[buf].obsidian_status = display_text
        end
      end)
    end)
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
