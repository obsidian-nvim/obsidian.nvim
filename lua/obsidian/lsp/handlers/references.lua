---@diagnostic disable: missing-fields

local util = require "obsidian.util"
local Note = require "obsidian.note"

-- TODO: references for anchor, blocks

---@param obsidian_client obsidian.Client
---@param _ table
---@param handler function
return function(obsidian_client, _, handler, _)
  local tag = util.cursor_tag(nil, nil)
  if tag then
    obsidian_client:find_tags_async(tag, function(tag_locations)
      local entries = {}
      for _, tag_loc in ipairs(tag_locations) do
        if tag_loc.tag == tag or vim.startswith(tag_loc.tag, tag .. "/") then
          local line = tag_loc.line - 1 -- lsp wants zero-indexed
          local tag_start = (tag_loc.tag_start or 1) - 1
          entries[#entries + 1] = {
            uri = vim.uri_from_fname(tostring(tag_loc.path)),
            range = {
              start = { line = line, character = tag_start },
              ["end"] = { line = line, character = tag_start },
            },
          }
        end
      end
      if vim.tbl_isempty(entries) then
        vim.notify("Tag not found", 3)
        return
      end
      handler(nil, entries)
    end, { search = { sort = true } })
  end

  local buf = vim.api.nvim_get_current_buf()

  local note = Note.from_buffer(buf)

  obsidian_client:find_backlinks_async(
    note,
    vim.schedule_wrap(function(backlinks)
      -- if vim.tbl_isempty(backlinks) then
      --   if opts.anchor then
      --     log.info("No backlinks found for anchor '%s' in note '%s'", opts.anchor, note.id)
      --   elseif opts.block then
      --     log.info("No backlinks found for block '%s' in note '%s'", opts.block, note.id)
      --   else
      --     log.info("No backlinks found for note '%s'", note.id)
      --   end
      --   return
      -- end
      --
      local entries = {}
      for _, matches in ipairs(backlinks) do
        for _, match in ipairs(matches.matches) do
          entries[#entries + 1] = {
            uri = vim.uri_from_fname(tostring(matches.path)),
            range = {
              start = { line = match.line, character = 1 },
              ["end"] = { line = match.line, character = 1 },
            },
          }
        end
      end

      handler(nil, entries)

      -- ---@type string
      -- local prompt_title
      -- if opts.anchor then
      --   prompt_title = string.format("Backlinks to '%s%s'", note.id, opts.anchor)
      -- elseif opts.block then
      --   prompt_title = string.format("Backlinks to '%s#%s'", note.id, util.standardize_block(opts.block))
      -- else
      --   prompt_title = string.format("Backlinks to '%s'", note.id)
      -- end
    end)
  )
end
