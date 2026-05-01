local log = require "obsidian.log"

return function(data)
  local query = vim.trim(data.args or "")

  local dir = Obsidian.workspaces[#Obsidian.workspaces].path

  if not dir then
    log.err "Failed to locate docs dir"
    return
  end

  if query ~= "" then
    local matches = {}

    local function check_path(p)
      if p:is_file() then
        table.insert(matches, p)
      end
    end

    check_path(dir / (query .. ".md"))
    check_path(dir / query)

    if #matches == 1 then
      vim.cmd("edit " .. tostring(matches[1]))
      return
    end
  end

  Obsidian.picker.find_notes {
    prompt_title = "Obsidian Help",
    dir = dir,
    query = query,
  }
end
