local M = {}
local api = require "obsidian.api"
local ns_id = vim.api.nvim_create_namespace "ObsidianFooter"

---@param buf integer
---@param is_visual boolean?
local function update_footer(buf, is_visual)
  local info = api.note_info(is_visual)
  if info == nil then
    return
  end
  local footer_text = assert(Obsidian.opts.footer.format)
  for k, v in pairs(info) do
    footer_text = footer_text:gsub("{{" .. k .. "}}", v)
  end
  local row0 = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)
  local col0 = 0
  local separator = Obsidian.opts.footer.separator
  local hl_group = Obsidian.opts.footer.hl_group
  local footer_contents = { { footer_text, hl_group } }
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

--- Register buffer-specific variables
M.start = function()
  local group = vim.api.nvim_create_augroup("obsidian_footer", {})
  local attached_bufs = {}
  vim.api.nvim_create_autocmd("User", {
    group = group,
    desc = "Initialize obsidian footer",
    pattern = "ObsidianNoteEnter",
    callback = function(ev)
      if attached_bufs[ev.buf] then
        return
      end
      vim.schedule(function()
        update_footer(ev.buf)
      end)
      local id = vim.api.nvim_create_autocmd({
        "FileChangedShellPost",
        "TextChanged",
        "TextChangedI",
        "TextChangedP",
      }, {
        group = group,
        desc = "Update obsidian footer",
        buffer = ev.buf,
        callback = vim.schedule_wrap(function()
          update_footer(ev.buf)
        end),
      })
      vim.api.nvim_create_autocmd("CursorMoved", {
        group = group,
        buffer = ev.buf,
        callback = vim.schedule_wrap(function(v)
          if vim.api.nvim_get_mode().mode:lower():find "v" then
            update_footer(ev.buf, true)
          end
        end),
      })
      attached_bufs[ev.buf] = id
    end,
  })
end

return M
