local h = dofile "tests/helpers.lua"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local M = require "obsidian.templates"
local Note = require "obsidian.note"

local T = new_set()

---Get a template context from a client.
---
---@param client obsidian.Client
---@param ctx? obsidian.TemplateContext|{}
---
---@return obsidian.TemplateContext ctx
local tmp_template_context = function(client, ctx)
  return vim.tbl_extend("keep", ctx or {}, {
    type = "insert_template",
    templates_dir = client:templates_dir(),
    template_opts = client.opts.templates,
    partial_note = Note.new("FOO", { "FOO" }, {}),
  })
end

T["substitute_template_variables()"] = new_set()

T["substitute_template_variables()"]["should substitute built-in variables"] = function()
  h.with_tmp_client(function(client)
    local text = "today is {{date}} and the title of the note is {{title}}"
    eq(
      string.format("today is %s and the title of the note is %s", os.date "%Y-%m-%d", "FOO"),
      M.substitute_template_variables(text, tmp_template_context(client))
    )
  end)
end

T["substitute_template_variables()"]["should substitute custom variables"] = function()
  h.with_tmp_client(function(client)
    client.opts.templates.substitutions = {
      weekday = function()
        return "Monday"
      end,
    }
    local text = "today is {{weekday}}"
    eq("today is Monday", M.substitute_template_variables(text, tmp_template_context(client)))

    eq(1, vim.tbl_count(client.opts.templates.substitutions))
    eq("function", type(client.opts.templates.substitutions.weekday))
  end)
end

T["substitute_template_variables()"]["should substitute consecutive custom variables"] = function()
  h.with_tmp_client(function(client)
    client.opts.templates.substitutions = {
      value = function()
        return "VALUE"
      end,
    }
    local text = "{{value}} and then {{value}} and then {{value}}"
    eq("VALUE and then VALUE and then VALUE", M.substitute_template_variables(text, tmp_template_context(client)))
  end)
end

T["substitute_template_variables()"]["should provide substitution functions with template context"] = function()
  h.with_tmp_client(function(client)
    client.opts.templates.substitutions = {
      test_var = function(ctx)
        return tostring(ctx.template_name)
      end,
    }
    local text = "my template is: {{test_var}}"
    local ctx = tmp_template_context(client, { template_name = "My Template.md" })
    eq("my template is: My Template.md", M.substitute_template_variables(text, ctx))
  end)
end

return T
