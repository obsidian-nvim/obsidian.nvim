local M = {}
local api = require "obsidian.api"

local ns_id = vim.api.nvim_create_namespace "ObsidianFooter"

--- Register buffer-specific variables
M.start = function(client)
  local current_note

  local refresh_footer_text = function(buf)
    local note = api.current_note(buf)
    if not note then -- no note
      return ""
    elseif current_note == note then -- no refresh
      return
    else -- refresh
      current_note = note
    end
    local format = assert(Obsidian.opts.footer.format)
    client:find_backlinks_async(
      note,
      vim.schedule_wrap(function(backlinks)
        local wc = vim.fn.wordcount()
        local info = {
          words = wc.words,
          chars = wc.chars,
          backlinks = #backlinks,
          properties = vim.tbl_count(note:frontmatter()),
        }
        for k, v in pairs(info) do
          format = format:gsub("{{" .. k .. "}}", v)
        end
        vim.b[buf].obsidian_footer_format = format
      end)
    )
    -- FIXME: Return backlinks synchronously on TextChanged events.
    -- local backlinks = client:find_backlinks(note)
    -- local wc = vim.fn.wordcount()
    -- local info = {
    --   words = wc.words,
    --   chars = wc.chars,
    --   backlinks = #backlinks,
    --   properties = vim.tbl_count(note:frontmatter()),
    -- }
    -- for k, v in pairs(info) do
    --   format = format:gsub("{{" .. k .. "}}", v)
    -- end
    -- return format
  end

  local function update_obsidian_footer(buf)
    local footer_text = refresh_footer_text(buf)
    -- TODO: Remove the redundant vim.wait if we can collect backlinks
    -- synchronously.
    vim.wait(100, function()
      footer_text = vim.b[buf].obsidian_footer_format
      return footer_text
    end)
    local row0 = #vim.api.nvim_buf_get_lines(buf, 0, -2, false)
    local col0 = 0
    local separator = string.rep("-", 80)
    local hl_group = "Comment"
    local footer_separator = { { separator, hl_group } }
    local footer_contents = { { footer_text, hl_group } }
    local footer_chunks = { footer_separator, footer_contents }
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
        callback = function()
          update_obsidian_footer(ev.buf)
        end,
      })
      attached_bufs[ev.buf] = id
    end,
  })
end

return M
