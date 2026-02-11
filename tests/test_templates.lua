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
    template_opts = Obsidian.opts.templates,
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

return T
