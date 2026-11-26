---@param commands obsidian.commands.Module
return function(commands)
  local register = commands.register

  ---@param ctx obsidian.commands.Context
  ---@return boolean
  local function in_note(ctx)
    return ctx.in_note
  end

  local function daily_enabled()
    return Obsidian.opts.daily_notes.enabled == true
  end

  local function templates_enabled()
    return Obsidian.opts.templates.enabled == true
  end

  register {
    name = "check",
    fn = function()
      return require "obsidian.commands.check"()
    end,
  }

  register {
    name = "today",
    nargs = "?",
    cond = daily_enabled,
    fn = function(data)
      return require "obsidian.commands.today"(data)
    end,
  }

  register {
    name = "yesterday",
    cond = daily_enabled,
    fn = function()
      return require "obsidian.commands.yesterday"()
    end,
  }

  register {
    name = "tomorrow",
    cond = daily_enabled,
    fn = function()
      return require "obsidian.commands.tomorrow"()
    end,
  }

  register {
    name = "dailies",
    nargs = "*",
    cond = daily_enabled,
    fn = function(data)
      return require "obsidian.commands.dailies"(data)
    end,
  }

  register {
    name = "new",
    nargs = "*",
    fn = function(data)
      local id = data.args:len() > 0 and data.args or nil
      require("obsidian.actions").new(id, function(note)
        note:open { sync = true }
      end)
    end,
  }

  register {
    name = "open",
    nargs = "*",
    complete = commands.note_complete,
    fn = function(data)
      return require "obsidian.commands.open"(data)
    end,
  }

  register {
    name = "tags",
    nargs = "*",
    fn = function(data)
      require("obsidian.actions").search_tags(data.fargs or {})
    end,
  }

  register {
    name = "properties",
    nargs = "*",
    fn = function(data)
      return require "obsidian.commands.properties"(data)
    end,
  }

  register {
    name = "search",
    nargs = "?",
    fn = function(data)
      require("obsidian.picker").grep_notes { query = data.args }
    end,
  }

  register {
    name = "sync",
    nargs = "?",
    cond = function()
      return Obsidian.opts.sync.enabled == true
    end,
    complete = function(arg)
      local choices = vim.tbl_map(function(action)
        return action.name
      end, require("obsidian.sync")._actions)

      return vim.tbl_filter(function(s)
        return vim.startswith(s, arg)
      end, choices)
    end,
    fn = function(data)
      return require "obsidian.commands.sync"(data)
    end,
  }

  register {
    name = "new_from_template",
    nargs = "*",
    cond = templates_enabled,
    fn = function(data)
      return require "obsidian.commands.new_from_template"(data)
    end,
  }

  register {
    name = "quick_switch",
    nargs = "?",
    fn = function(data)
      require("obsidian.picker").find_notes {
        prompt_title = "Quick Switch",
        query = data.args ~= "" and data.args or nil,
        show_existing_only = Obsidian.opts.quick_switch.show_existing_only,
        show_attachments = Obsidian.opts.quick_switch.show_attachments,
      }
    end,
  }

  register {
    name = "rebuild_cache",
    fn = function()
      return require "obsidian.commands.rebuild_cache"()
    end,
  }

  register {
    name = "workspace",
    nargs = "?",
    fn = function(data)
      return require "obsidian.commands.workspace"(data)
    end,
  }

  register {
    name = "help",
    nargs = "?",
    complete = commands.help_complete,
    fn = function(data)
      return require "obsidian.commands.help"(data)
    end,
  }

  register {
    name = "helpgrep",
    nargs = "?",
    fn = function(data)
      return require "obsidian.commands.helpgrep"(data)
    end,
  }

  register {
    name = "unique_note",
    nargs = "?",
    cond = function()
      return Obsidian.opts.unique_note.enabled == true
    end,
    fn = function()
      require("obsidian.actions").unique_note()
    end,
  }

  register {
    name = "bookmarks",
    fn = function()
      return require "obsidian.commands.bookmarks"()
    end,
  }

  register {
    name = "backlinks",
    cond = in_note,
    fn = function()
      return require "obsidian.commands.backlinks"()
    end,
  }

  register {
    name = "template",
    nargs = "?",
    cond = function(ctx)
      return ctx.in_note and templates_enabled()
    end,
    fn = function(data)
      return require "obsidian.commands.template"(data)
    end,
  }

  register {
    name = "link_new",
    nargs = "?",
    cond = in_note,
    fn = function(data)
      require("obsidian.actions").link_new(data.args, require("obsidian.api").get_visual_selection())
    end,
  }

  register {
    name = "link",
    nargs = "?",
    complete = commands.note_complete,
    cond = in_note,
    fn = function()
      require("obsidian.actions").link(require("obsidian.api").get_visual_selection())
    end,
  }

  register {
    name = "links",
    cond = in_note,
    fn = function()
      return require "obsidian.commands.links"()
    end,
  }

  register {
    name = "follow_link",
    nargs = "?",
    cond = in_note,
    fn = function(data)
      return require "obsidian.commands.follow_link"(data)
    end,
  }

  register {
    name = "toggle_checkbox",
    range = true,
    cond = function(ctx)
      return ctx.in_note and Obsidian.opts.checkbox.enabled == true
    end,
    fn = function(data)
      require("obsidian.actions").toggle_checkbox(data.line1, data.line2)
    end,
  }

  register {
    name = "rename",
    nargs = "?",
    cond = in_note,
    fn = function(data)
      return require "obsidian.commands.rename"(data)
    end,
  }

  register {
    name = "paste_img",
    nargs = "?",
    cond = in_note,
    fn = function(data)
      return require "obsidian.commands.paste_img"(data)
    end,
  }

  register {
    name = "extract_note",
    nargs = "?",
    range = true,
    cond = function(ctx)
      return ctx.in_note and ctx.has_range
    end,
    fn = function(data)
      local extract_note = require("obsidian.actions").extract_note
      if data.range and data.range > 0 then
        extract_note(data.args, data.line1, data.line2)
      else
        extract_note(data.args)
      end
    end,
  }

  register {
    name = "toc",
    cond = in_note,
    fn = function()
      return require "obsidian.commands.toc"()
    end,
  }

  register {
    name = "footnotes",
    cond = in_note,
    fn = function()
      require("obsidian.footnotes").pick()
    end,
  }
end
