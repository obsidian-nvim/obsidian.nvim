local embed = require "obsidian.embed"
local search = require "obsidian.search"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local T = new_set()

T["start renders the note body below an embed"] = function()
  local original_resolve_note = search.resolve_note
  local ok, err = pcall(function()
    search.resolve_note = function(note_id)
      eq(note_id, "target")
      return {
        {
          contents = { "---", "title: Target", "---", "**body**" },
          frontmatter_end_line = 3,
        },
      }
    end

    local buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "![[target#section|alias]]" })
    embed.start(buf)

    local namespace = vim.api.nvim_create_namespace "obsidian-nvim-embeds"
    local marks = vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, { details = true })
    eq(#marks, 1)
    eq(marks[1][4].virt_lines, {
      {
        { "▏", "NonText" },
        { "body", "@markup.strong.markdown_inline" },
      },
    })

    search.resolve_note = function()
      return {}
    end
    embed.start(buf)
    eq(#vim.api.nvim_buf_get_extmarks(buf, namespace, 0, -1, {}), 0)
  end)
  search.resolve_note = original_resolve_note
  if not ok then
    error(err)
  end
end

return T
