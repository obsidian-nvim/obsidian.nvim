local util = require "obsidian.util"
local RefTypes = require("obsidian.search").RefTypes
local api = require "obsidian.api"
local search = require "obsidian.search"

-- TODO: jump to block and anchor

local query2pos = function(contents, query)
  local pos = {}
  for idx, content in ipairs(contents) do
    local st, ed = string.find(content, query)
    if st and ed then
      pos[#pos + 1] = {
        start = { line = idx - 1, character = st - 1 },
        ["end"] = { line = idx - 1, character = ed - 1 },
      }
    end
  end
  return pos
end

---@param params lsp.ReferenceParams
---@param handler fun(_:any, loactions: lsp.Location[])
return function(params, handler)
  local cur_link, link_type = api.cursor_link()

  local uri

  local range = {
    start = { line = 0, character = 0 },
    ["end"] = { line = 0, character = 0 },
  }

  if
    cur_link
    and link_type ~= RefTypes.NakedUrl
    and link_type ~= RefTypes.FileUrl
    and link_type ~= RefTypes.BlockID
  then
    local location = util.parse_link(cur_link, { include_block_ids = true })
    assert(location, "cursor on a link but failed to parse, please report to repo")

    -- Remove block links from the end if there are any.
    -- TODO: handle block links.
    ---@type string|?
    local block_link
    location, block_link = util.strip_block_links(location)

    -- Remove anchor links from the end if there are any.
    ---@type string|?
    local anchor_link
    location, anchor_link = util.strip_anchor_links(location)

    -- Assume 'location' is current buffer path if empty, like for TOCs.
    if string.len(location) == 0 then
      location = vim.api.nvim_buf_get_name(0)
    end

    local note = search.resolve_note(location)
    uri = vim.uri_from_fname(tostring(note.path)) or nil
    note:load_content()
    for _, q in ipairs { anchor_link, block_link } do
      local r = query2pos(note.contents, q)
      if r then
        range = r
      end
    end
  end

  handler(nil, {
    uri = uri,
    range = range,
  })
end
