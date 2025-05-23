local log = require "obsidian.log"
local templates = require "obsidian.templates"
local util = require "obsidian.util"

---@param client obsidian.Client
---@param data CommandArgs
return function(client, data)
  if not client:templates_dir() then
    log.err "Templates folder is not defined or does not exist"
    return
  end

  -- We need to get this upfront before the picker hijacks the current window.
  local cursor_location = util.get_active_window_cursor_location()

  local function insert_template(template_path)
    templates.insert_template {
      action = "insert_template",
      client = client,
      template = template_path,
      target_location = cursor_location,
    }
  end

  if string.len(data.args) > 0 then
    local template_name = util.strip_whitespace(data.args)
    insert_template(template_name)
    return
  end

  local picker = client:picker()
  if not picker then
    log.err "No picker configured"
    return
  end

  picker:find_templates {
    callback = function(path)
      insert_template(path)
    end,
  }
end
