local obsidian = require "obsidian"
local has_nvim_0_12 = vim.fn.has "nvim-0.12.0" == 1

-- -- TODO: neovim's visual selection is weird
-- local label = vim.api.nvim_buf_get_text(
--   0,
--   range.start.line,
--   range.start.character,
--   range["end"].line,
--   range["end"].character,
--   {}
-- )[1]
--

return {
  ---@param range lsp.Range
  ---@return lsp.WorkspaceEdit?
  edit = function(range)
    -- print(range.start.line, range["end"].line)
    -- if range.start.line ~= range["end"].line then
    --   obsidian.log.err "Only in-line visual selections allowed"
    --   return
    -- end
    --
    -- require("obsidian.note").create { title = label }
    -- obsidian.api.make_text_edit()
    -- return {
    --   documentChanges = {
    --     {
    --       textDocument = {
    --         uri = vim.uri_from_fname(vim.api.nvim_buf_get_name(0)),
    --         version = has_nvim_0_12 and vim.NIL or nil,
    --       },
    --       edits = {
    --         {
    --           range = range,
    --           newText = label,
    --         },
    --       },
    --     },
    --   },
    -- }
    local label

    local viz = obsidian.api.get_visual_selection()
    if not viz then
      obsidian.log.err "`Obsidian link_new` must be called in visual mode"
      return
    elseif #viz.lines ~= 1 then
      obsidian.log.err "Only in-line visual selections allowed"
      return
    end

    if not label or string.len(label) <= 0 then
      label = viz.selection
    end

    local note = require("obsidian.note").create { title = label }
    local text_edit = obsidian.api.make_text_edit(viz, note:format_link { label = label })
    return { documentChanges = { text_edit } }
  end,
  command = function()
    -- Save file so backlinks search (ripgrep) can find the new link
    vim.cmd "silent! write" -- HACK:
  end,
}
