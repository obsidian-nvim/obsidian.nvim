local M = {}
local obsidian = require "obsidian"
local ns_id = vim.api.nvim_create_namespace "ObsidianFooter"

---@param buf integer
---@param update_backlinks boolean|?
local update_footer = vim.schedule_wrap(function(buf, update_backlinks)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local note = obsidian.Note.from_buffer(buf)
  if note == nil then
    return
  end
  local info = note:status(update_backlinks)
  if info == nil then
    return
  end
  local footer_format = Obsidian.opts.footer.format ---@cast footer_format -nil
  for k, v in pairs(info) do
    footer_format = footer_format:gsub("{{" .. k .. "}}", v)
  end
  local row0 = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)
  local col0 = 0
  local separator = Obsidian.opts.footer.separator
  local hl_group = Obsidian.opts.footer.hl_group
  local footer_contents = { { footer_format, hl_group } }
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
end)

vim.g.obsidian_footer_update_interval = 10000

--- Register buffer-specific variables
M.start = function()
  local group = vim.api.nvim_create_augroup("obsidian_footer", {})
  local attached_bufs = {}
  local timers = {}
  vim.api.nvim_create_autocmd("User", {
    group = group,
    desc = "Initialize obsidian footer",
    pattern = "ObsidianNoteEnter",
    callback = function(ev)
      if attached_bufs[ev.buf] then
        return
      end
      update_footer(ev.buf)
      local id = vim.api.nvim_create_autocmd({
        "FileChangedShellPost",
        "TextChanged",
        "TextChangedI",
        "TextChangedP",
      }, {
        group = group,
        desc = "Update obsidian footer",
        buffer = ev.buf,
        callback = function()
          update_footer(ev.buf)
        end,
      })
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = ev.buf,
        callback = function()
          if vim.api.nvim_get_mode().mode:lower():find "v" then
            update_footer(ev.buf)
          end
        end,
      })

      local timer = vim.uv:new_timer()
      assert(timer, "Failed to create timer")
      timer:start(0, vim.g.obsidian_footer_update_interval, function()
        update_footer(ev.buf, true)
      end)

      timers[ev.buf] = timer
      attached_bufs[ev.buf] = id

      vim.api.nvim_create_autocmd("BufWipeout", {
        group = group,
        buffer = ev.buf,
        callback = function()
          local buf_timer = timers[ev.buf]
          if buf_timer then
            buf_timer:stop()
            buf_timer:close()
            timers[ev.buf] = nil
          end
          attached_bufs[ev.buf] = nil
        end,
      })
    end,
  })
end

return M
