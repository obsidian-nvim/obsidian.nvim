local util = require "obsidian.util"

--- TODO: hover on tags
--- TODO: should not work on frontmatter?

local function read_file(file)
  local fd = assert(io.open(file, "r"))
  ---@type string
  local data = fd:read "*a"
  fd:close()
  return data
end

---@param obsidian_client obsidian.Client
---@param params table
---@param handler function
return function(obsidian_client, params, handler, _)
  local term = util.parse_cursor_link()
  if term then
    obsidian_client:find_notes_async(
      term,
      vim.schedule_wrap(function(notes)
        for i, note in ipairs(notes) do
          if vim.uri_from_fname(note.path.filename) == params.textDocument.uri then
            table.remove(notes, i)
          end
        end
        local note = notes[1]
        if note then
          handler(nil, {
            contents = read_file(note.path.filename),
          })
        else
          vim.notify("No notes found", 3)
        end
      end)
    )
  else
    vim.notify("No notes found", 3)
  end
end
