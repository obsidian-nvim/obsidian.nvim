local util = require "obsidian.util"
local log = require "obsidian.log"
local templates = require "obsidian.templates"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  local picker = client:picker()
  if not picker then
    log.err "No picker configured"
    return
  end

  local title = table.concat(data.fargs, " ", 1, #data.fargs - 1)
  local template = data.fargs[#data.fargs]

  if title ~= nil and template ~= nil then
    templates.load_template_customizations(template, client)
    local note = client:create_note { title = title, template = template, no_write = false }
    client:open_note(note, { sync = true })
    templates.restore_client_configurations(client)
    return
  end

  picker:find_templates {
    callback = function(name)
      templates.load_template_customizations(name, client)
      if title == nil or title == "" then
        -- Must use pcall in case of KeyboardInterrupt
        -- We cannot place `title` where `safe_title` is because it would be redeclaring it
        local success, safe_title = pcall(util.input, "Enter title or path (optional): ", { completion = "file" })
        title = safe_title
        if not success or not safe_title then
          log.warn "Aborted"
          templates.restore_client_configurations(client)
          return
        elseif safe_title == "" then
          title = nil
        end
      end

      if name == nil or name == "" then
        log.warn "Aborted"
        templates.restore_client_configurations(client)
        return
      end

      ---@type obsidian.Note
      local note = client:create_note { title = title, template = name, no_write = false }
      client:open_note(note, { sync = false })
      templates.restore_client_configurations(client)
    end,
  }
end
