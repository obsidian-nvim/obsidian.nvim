local api = require "obsidian.api"
local log = require "obsidian.log"
local picker = require "obsidian.picker"

return function(data)
  local query = vim.trim(data.args or "")
  local docs_dir = api.docs_dir()
    or (Obsidian.workspaces[#Obsidian.workspaces] and Obsidian.workspaces[#Obsidian.workspaces].path)
  if not docs_dir then
    return log.err "Failed to locate docs dir"
  end

  if query ~= "" then
    local normalized_query = query:gsub("%.md$", ""):lower()
    local matches = {}
    for path, kind in vim.fs.dir(tostring(docs_dir)) do
      if kind == "file" and vim.endswith(path:lower(), ".md") then
        local basename = vim.fn.fnamemodify(path, ":t:r")
        if basename:lower() == normalized_query then
          matches[#matches + 1] = vim.fs.joinpath(tostring(docs_dir), path)
        end
      end
    end
    if #matches == 1 then
      vim.cmd("edit " .. vim.fn.fnameescape(matches[1]))
      return
    end
  end

  picker.find_notes {
    prompt_title = "Obsidian Help",
    dir = docs_dir,
    query = query,
  }
end
