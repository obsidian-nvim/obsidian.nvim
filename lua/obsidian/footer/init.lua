local M = {}
local api = require "obsidian.api"
local search = require "obsidian.search"

local ns_id = vim.api.nvim_create_namespace "ObsidianFooter"

--- Register buffer-specific variables
M.start = function()
  local refresh_info = function(buf)
    local note = api.current_note(buf)
    if not note then
      return
    end
    local info = {}
    local wc = vim.fn.wordcount()
    info.words = wc.words
    info.chars = wc.chars
    info.properties = vim.tbl_count(note:frontmatter())
    info.backlinks = #search.find_backlinks(note)
    return info
  end

  local function update_obsidian_footer(buf)
    local info = refresh_info(buf)
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
        update_obsidian_footer(ev.buf)
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
          update_obsidian_footer(ev.buf)
        end),
      })
      attached_bufs[ev.buf] = id
    end,
  })
end

return M
