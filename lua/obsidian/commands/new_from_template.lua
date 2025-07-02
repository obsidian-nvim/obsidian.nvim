local log = require "obsidian.log"
local util = require "obsidian.util"
local Note = require "obsidian.note"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  local picker = client:picker()
  if not picker then
    log.err "No picker configured"
    return
  end

  ---@type string?
  local title = table.concat(data.fargs, " ", 1, #data.fargs - 1)
  local template = data.fargs[#data.fargs]

  if title ~= nil and template ~= nil then
    local note = Note.create { title = title, template = template, should_write = true }
    client:open_note(note, { sync = true })
    return
  end

  picker:find_templates {
    callback = function(template_name)
      if title == nil or title == "" then
        -- Must use pcall in case of KeyboardInterrupt
        -- We cannot place `title` where `safe_title` is because it would be redeclaring it
        local success, safe_title = pcall(util.input, "Enter title or path (optional): ", { completion = "file" })
        title = safe_title
        if not success or not safe_title then
          log.warn "Aborted"
          return
        elseif safe_title == "" then
          title = nil
        end
      end

      if template_name == nil or template_name == "" then
        log.warn "Aborted"
        return
      end

      ---@type obsidian.Note
      local note = Note.create { title = title, template = template_name, should_write = true }
      client:open_note(note, { sync = false })
    end,
  }
end
