local templates = require "obsidian.templates"
local log = require "obsidian.log"
local api = require "obsidian.api"

---@param data obsidian.CommandArgs
return function(data)
  local templates_dir = api.templates_dir()
  if not templates_dir then
    return log.err "Templates folder is not defined or does not exist"
  end

  -- We need to get this upfront before the picker hijacks the current window.
  local insert_location = api.get_active_window_cursor_location()

  local function insert_template(name)
    templates.insert_template {
      type = "insert_template",
      template_name = name,
      template_opts = Obsidian.opts.templates,
      templates_dir = templates_dir,
      location = insert_location,
    }
  end

  if string.len(data.args) > 0 then
    local template_name = vim.trim(data.args)
    insert_template(template_name)
    return
  end

  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  local paths = vim
    .iter(vim.fs.dir(tostring(templates_dir)))
    :map(function(fname)
      return {
        filename = tostring(templates_dir / fname),
        value = templates_dir / fname,
        display = fname,
      }
    end)
    :totable()

  picker.pick(paths, {
    prompt_title = "Templates",
    callback = function(entry)
      insert_template(entry.filename)
    end,
  })
end
