local log = require "obsidian.log"
local search = require "obsidian.search"
local iter = vim.iter
local util = require "obsidian.util"
local table, string = table, string

---@param client obsidian.Client
return function(client)
  local picker = client:picker()
  if not picker then
    log.err "No picker configured"
    return
  end

  -- Gather all unique raw links (strings) from the buffer.
  ---@type table<string, integer>
  local links = {}
  for lnum, line in ipairs(vim.api.nvim_buf_get_lines(0, 0, -1, true)) do
    for match in iter(search.find_refs(line, { include_naked_urls = true, include_file_urls = true })) do
      local m_start, m_end = unpack(match)
      local link = string.sub(line, m_start, m_end)
      if not links[link] then
        links[link] = lnum
      end
    end
  end

  ---@type obsidian.PickerEntry[]
  local entries = {}
  local done = 0
  local n_tasks = vim.tbl_count(links)

  local function on_exit()
    table.sort(entries, function(a, b)
      return links[a.value] < links[b.value] -- Sort by line number within the buffer.
    end)
    picker:pick(entries, {
      prompt_title = "Links",
      callback = function(link)
        client:follow_link_async(link)
      end,
    })
  end

  for link in vim.iter(links) do
    client:resolve_link_async(link, function(...)
      for res in iter { ... } do
        local icon, icon_hl
        if res.url ~= nil then
          icon, icon_hl = util.get_icon(res.url)
        end
        table.insert(entries, {
          value = link,
          display = res.name,
          filename = res.path and tostring(res.path) or nil,
          icon = icon,
          icon_hl = icon_hl,
          lnum = res.line,
          col = res.col,
        })
      end
      done = done + 1
      if done == n_tasks then
        on_exit()
      end
    end)
  end
end
