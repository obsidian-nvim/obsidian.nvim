local T = dofile("tests/helpers.lua").temp_vault
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local M = require "obsidian.templates"
local moment = require "obsidian.lib.moment"
local Note = require "obsidian.note"
local api = require "obsidian.api"
require "obsidian.client"

---Get a template context from a client.
---
---@param ctx? obsidian.TemplateContext|{}
---
---@return obsidian.TemplateContext ctx
local tmp_template_context = function(ctx)
  return vim.tbl_extend("keep", ctx or {}, {
    type = "insert_template",
    templates_dir = api.templates_dir(),
    partial_note = Note.new("FOO", { "FOO" }, {}),
  })
end

T["substitute_template_variables()"] = new_set()

T["substitute_template_variables()"]["should substitute built-in variables"] = function()
  local text = "today is {{date}} and the title of the note is {{title}}"
  eq(
    string.format("today is %s and the title of the note is %s", os.date "%Y-%m-%d", "FOO"),
    M.substitute_template_variables(text, tmp_template_context())
  )
end

T["substitute_template_variables()"]["should support moment date_format"] = function()
  local previous = Obsidian.opts.templates.date_format
  Obsidian.opts.templates.date_format = "YYYY-MM-DD"

  local text = "today is {{date}}"
  eq(
    string.format("today is %s", moment.format(os.time(), "YYYY-MM-DD")),
    M.substitute_template_variables(text, tmp_template_context())
  )

  Obsidian.opts.templates.date_format = previous
end

T["substitute_template_variables()"]["should support template suffix"] = function()
  local text = "year is {{date:YYYY}} and hour is {{time:HH}}"
  eq(
    string.format("year is %s and hour is %s", moment.format(os.time(), "YYYY"), moment.format(os.time(), "HH")),
    M.substitute_template_variables(text, tmp_template_context())
  )
end

T["substitute_template_variables()"]["should substitute custom variables"] = function()
  Obsidian.opts.templates.substitutions = {
    weekday = function()
      return "Monday"
    end,
  }
  local text = "today is {{weekday}}"
  eq("today is Monday", M.substitute_template_variables(text, tmp_template_context()))

  eq(1, vim.tbl_count(Obsidian.opts.templates.substitutions))
  eq("function", type(Obsidian.opts.templates.substitutions.weekday))
end

T["substitute_template_variables()"]["should substitute consecutive custom variables"] = function()
  Obsidian.opts.templates.substitutions = {
    value = function()
      return "VALUE"
    end,
  }
  local text = "{{value}} and then {{value}} and then {{value}}"
  eq("VALUE and then VALUE and then VALUE", M.substitute_template_variables(text, tmp_template_context()))
end

T["substitute_template_variables()"]["should substitute string values"] = function()
  Obsidian.opts.templates.substitutions = {
    username = "obsidian-nvim",
  }
  local text = "author: {{username}}"
  eq("author: obsidian-nvim", M.substitute_template_variables(text, tmp_template_context()))
end

T["substitute_template_variables()"]["should provide substitution functions with template context"] = function()
  Obsidian.opts.templates.substitutions = {
    test_var = function(ctx)
      return tostring(ctx.template_name)
    end,
  }
  local text = "my template is: {{test_var}}"
  local ctx = tmp_template_context { template_name = "My Template.md" }
  eq("my template is: My Template.md", M.substitute_template_variables(text, ctx))
end

T["substitute_template_variables()"]["should pass suffix to substitution functions"] = function()
  Obsidian.opts.templates.substitutions = {
    test_var = function(_, suffix)
      return string.format("%s", suffix)
    end,
  }
  local text = "value is {{test_var:hello}}"
  eq("value is hello", M.substitute_template_variables(text, tmp_template_context()))
end

T["clone_template()"] = new_set()

T["clone_template()"]["should transfer title from partial_note"] = function()
  vim.fn.writefile({}, tostring(Obsidian.dir / "templates" / "basic.md"))

  local destination = Obsidian.dir / "test-note.md"
  local partial = Note.new("1234-ABCD", {}, {}, nil, "My Note Title")

  local result = M.clone_template {
    type = "clone_template",
    template_name = "basic.md",
    destination_path = destination,
    templates_dir = api.templates_dir(),
    partial_note = partial,
  }

  eq("My Note Title", result.title)
end

T["has_templater_js()"] = new_set()

T["has_templater_js()"]["should detect Templater execution markers"] = function()
  eq(true, M.has_templater_js("<% tp.date.now() %>"))
  eq(true, M.has_templater_js("<%= tp.date.now() %>"))
  eq(true, M.has_templater_js("<%# comment %>"))
end

T["has_templater_js()"]["should detect js code block in first 10 lines"] = function()
  local content = "# Title\n\n```js\nconsole.log('hello');\n```\n\nSome text."
  eq(true, M.has_templater_js(content))
end

T["has_templater_js()"]["should not detect js code block after first 10 lines"] = function()
  local lines = {}
  for i = 1, 11 do
    lines[#lines + 1] = "line " .. i
  end
  lines[#lines + 1] = "```js"
  local content = table.concat(lines, "\n")
  eq(false, M.has_templater_js(content))
end

T["has_templater_js()"]["should return false for plain markdown"] = function()
  eq(false, M.has_templater_js("# Hello\n\nJust some text."))
  eq(false, M.has_templater_js("{{date}}\n\n{{title}}"))
end

T["is_templater_template()"] = new_set()

T["is_templater_template()"]["should return true for template with Templater syntax"] = function()
  local templates_dir = Obsidian.dir / "templates"
  templates_dir:mkdir { parents = true, exist_ok = true }
  local template_path = templates_dir / "templater-note.md"
  vim.fn.writefile(
    { "<% tp.date.now(\"YYYY-MM-DD\") %>", "", "# My Note" },
    tostring(template_path)
  )
  eq(true, M.is_templater_template("templater-note.md", templates_dir))
end

T["is_templater_template()"]["should return false for plain template"] = function()
  local templates_dir = Obsidian.dir / "templates"
  templates_dir:mkdir { parents = true, exist_ok = true }
  local template_path = templates_dir / "plain-note.md"
  vim.fn.writefile(
    { "{{date}}", "", "# {{title}}" },
    tostring(template_path)
  )
  eq(false, M.is_templater_template("plain-note.md", templates_dir))
end

T["config.normalize()"] = new_set()

T["config.normalize()"]["custom substitutions should not clobber defaults"] = function()
  local config = require "obsidian.config"
  local opts = config.normalize {
    workspaces = { { path = tostring(Obsidian.dir) } },
    templates = {
      substitutions = {
        weekday = function()
          return "Monday"
        end,
      },
    },
  }

  -- User's custom substitution should be present.
  eq("function", type(opts.templates.substitutions.weekday))

  -- Default substitutions should also be present.
  eq("function", type(opts.templates.substitutions.date))
  eq("function", type(opts.templates.substitutions.time))
  eq("function", type(opts.templates.substitutions.title))
  eq("function", type(opts.templates.substitutions.id))
  eq("function", type(opts.templates.substitutions.path))
end

T["config.normalize()"]["custom ui checkboxes should not clobber defaults"] = function()
  local config = require "obsidian.config"
  local opts = config.normalize {
    workspaces = { { path = tostring(Obsidian.dir) } },
    ui = {
      checkboxes = {
        ["?"] = { char = "", hl_group = "ObsidianQuestion" },
      },
    },

    legacy_commands = false,
  }

  -- User's custom checkbox should be present.
  eq("", opts.ui.checkboxes["?"].char)

  -- Default checkboxes should also be present.
  eq("obsidiantodo", opts.ui.checkboxes[" "].hl_group)
  eq("obsidiandone", opts.ui.checkboxes["x"].hl_group)
  eq("obsidiantilde", opts.ui.checkboxes["~"].hl_group)
end

T["config.normalize()"]["list_fields should append rather than replace"] = function()
  local config = require "obsidian.config"
  local opts = config.normalize {
    workspaces = { { path = tostring(Obsidian.dir) } },
    open = {
      schemes = { "obsidian" },
    },
    legacy_commands = false,
  }

  -- User's custom scheme should be present.
  eq(true, vim.tbl_contains(opts.open.schemes, "obsidian"))

  -- Default schemes should also be present (appended, not replaced).
  eq(true, vim.tbl_contains(opts.open.schemes, "https"))
  eq(true, vim.tbl_contains(opts.open.schemes, "http"))
  eq(true, vim.tbl_contains(opts.open.schemes, "file"))
  eq(true, vim.tbl_contains(opts.open.schemes, "mailto"))
end

T["config.normalize()"]["vim.NIL should remove a default value"] = function()
  local config = require "obsidian.config"
  local opts = config.normalize {
    workspaces = { { path = tostring(Obsidian.dir) } },
    new_notes_location = vim.NIL,
  }

  -- The field should be nil, not the default "current_dir".
  eq(nil, opts.new_notes_location)
end

T["config.normalize()"]["templater defaults should apply when not overridden"] = function()
  local config = require "obsidian.config"
  local opts = config.normalize {
    workspaces = { { path = tostring(Obsidian.dir) } },
  }

  eq(false, opts.templater.enabled)
  eq("templater", opts.templater.cmd)
  eq(true, opts.templater.pipe_stdin)
end

T["config.normalize()"]["templater overrides should merge with defaults"] = function()
  local config = require "obsidian.config"
  local opts = config.normalize {
    workspaces = { { path = tostring(Obsidian.dir) } },
    templater = {
      enabled = true,
      cmd = "custom-templater",
    },
  }

  eq(true, opts.templater.enabled)
  eq("custom-templater", opts.templater.cmd)
  -- Default pipe_stdin should still be present.
  eq(true, opts.templater.pipe_stdin)
end

return T
