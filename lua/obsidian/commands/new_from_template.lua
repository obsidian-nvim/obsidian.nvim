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
  local title = table.concat(data.fargs, " ", 1, #data.fargs - 1)
  local template = data.fargs[#data.fargs]

  if title ~= nil and template ~= nil then
    local note = Note.create { title = title, template = template, should_write = true }
    note:open { sync = true }
    return
  end

  local paths = vim
    .iter(vim.fs.dir(tostring(templates_dir)))
    :map(function(fname)
      -- return tostring(templates_dir / fname)
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
      local template_name = entry.filename

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
      note:open { sync = false }
    end,
  })
end
