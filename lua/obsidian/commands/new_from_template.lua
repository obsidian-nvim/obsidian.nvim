local log = require "obsidian.log"
local util = require "obsidian.util"
local api = require "obsidian.api"
local Note = require "obsidian.note"

---@param data obsidian.CommandArgs
return function(data)
  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  local templates_dir = api.templates_dir()
  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end

  ---@type string?
  local id = table.concat(data.fargs, " ", 1, #data.fargs - 1)
  local template = data.fargs[#data.fargs]

  if id ~= nil and template ~= nil then
    local note = Note.create { id = id, template = template, should_write = true }
    note:open { sync = true }
    return
  end

  picker.find_files {
    prompt_title = "Templates",
    dir = templates_dir,
    no_default_mappings = true,
    callback = function(template_name)
      if id == nil or id == "" then
        -- Must use pcall in case of KeyboardInterrupt
        -- We cannot place `title` where `safe_title` is because it would be redeclaring it
        local success, safe_title = pcall(util.input, "Enter title or path (optional): ", { completion = "file" })
        id = safe_title
        if not success or not safe_title then
          log.warn "Aborted"
          return
        elseif safe_title == "" then
          id = nil
        end
      end

      if template_name == nil or template_name == "" then
        log.warn "Aborted"
        return
      end

      ---@type obsidian.Note
      local note = Note.create { id = id, template = template_name, should_write = true }
      note:open { sync = false }
    end,
  }
end
