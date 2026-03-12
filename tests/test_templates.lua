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

T["substitute_template_variables()"]["should evaluate lua expressions"] = function()
  local text = "sum is {{= 1 + 2 }}"
  eq("sum is 3", M.substitute_template_variables(text, tmp_template_context()))
end

T["substitute_template_variables()"]["should evaluate lua expressions with braces"] = function()
  local text = "value is {{= ({ value = 2 }).value + 1 }}"
  eq("value is 3", M.substitute_template_variables(text, tmp_template_context()))
end

T["substitute_template_variables()"]["should execute lua blocks"] = function()
  local text = table.concat({
    "Tags:",
    "{{lua",
    "for _, tag in ipairs(tags) do",
    "  print('- #' .. tag)",
    "end",
    "}}",
  }, "\n")

  local out = M.substitute_template_variables(text, vim.tbl_extend("force", tmp_template_context(), {
    tags = { "nvim", "lua" },
  }))

  eq(table.concat({ "Tags:", "- #nvim", "- #lua" }, "\n"), out)
end

T["substitute_template_variables()"]["should preserve indentation for lua block output"] = function()
  local text = table.concat({
    "tags:",
    "  {{lua",
    "  for _, tag in ipairs(tags) do",
    "    print('- ' .. tag)",
    "  end",
    "  }}",
  }, "\n")

  local out = M.substitute_template_variables(text, vim.tbl_extend("force", tmp_template_context(), {
    tags = { "nvim", "lua" },
  }))

  eq(table.concat({ "tags:", "  - nvim", "  - lua" }, "\n"), out)
end

T["substitute_template_variables()"]["should return readable error for bad expression"] = function()
  local text = "bad: {{= missing_fn() }}"
  local out = M.substitute_template_variables(text, tmp_template_context())
  eq(true, string.match(out, "^bad: %[template error: .+%]$") ~= nil)
end

T["substitute_template_variables()"]["should return readable error for bad lua block"] = function()
  local text = table.concat({
    "{{lua",
    "error('boom')",
    "}}",
  }, "\n")
  local out = M.substitute_template_variables(text, tmp_template_context())
  eq(true, string.match(out, "^%[template error: .+%]$") ~= nil)
end

T["substitute_template_variables()"]["should only prompt for identifier variables"] = function()
  local original_input = api.input
  local prompted = false
  local ok, out

  api.input = function(_)
    prompted = true
    return ""
  end

  ok, out = pcall(M.substitute_template_variables, "{{foo.bar}}", tmp_template_context())
  api.input = original_input

  if not ok then
    error(out)
  end

  eq("{{foo.bar}}", out)
  eq(false, prompted)
end

T["substitute_template_variables()"]["should prompt for unknown identifier variables"] = function()
  local original_input = api.input
  local prompted = false
  local ok, out

  api.input = function(prompt)
    prompted = string.match(prompt, "unknown") ~= nil
    return "VALUE"
  end

  ok, out = pcall(M.substitute_template_variables, "x={{unknown}}", tmp_template_context())
  api.input = original_input

  if not ok then
    error(out)
  end

  eq("x=VALUE", out)
  eq(true, prompted)
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

return T
