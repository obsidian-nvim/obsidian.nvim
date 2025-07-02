local h = dofile "tests/helpers.lua"
local new_set, eq, neq = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.no_equality
local M = require "obsidian.templates"
local Note = require "obsidian.note"
require "obsidian.client"

--- @type obsidian.config.CustomTemplateOpts
local zettelConfig = {
  notes_subdir = "/custom/path/to/zettels",
  note_id_func = function()
    return "hummus"
  end,
}

local T = new_set()

---Get a template context from a client.
---
---@param ctx? obsidian.TemplateContext|{}
---
---@return obsidian.TemplateContext ctx
local tmp_template_context = function(ctx)
  return vim.tbl_extend("keep", ctx or {}, {
    type = "insert_template",
    templates_dir = M.get_template_dir(),
    template_opts = Obsidian.opts.templates,
    partial_note = Note.new("FOO", { "FOO" }, {}),
  })
end

T["substitute_template_variables()"] = new_set()
T["load_template_customizations()"] = new_set()
T["restore_client_configurations()"] = new_set()

T["load_template_customizations()"]["should not load customizations for non-existent templates"] = function()
  h.with_tmp_client(function()
    Obsidian.opts.templates.customizations = {
      Zettel = zettelConfig,
    }
    local old_id_func = Obsidian.opts.note_id_func

    M.load_template_customizations "zettel"

    eq(Obsidian.opts.notes_subdir, nil)
    neq(zettelConfig.note_id_func, Obsidian.opts.note_id_func)
    eq(old_id_func, Obsidian.opts.note_id_func)
  end, nil, { templates = { folder = "templates" } })
end

T["load_template_customizations()"]["should load customizations for existing template"] = function()
  h.with_tmp_client(function()
    Obsidian.opts.templates.customizations = {
      Zettel = zettelConfig,
    }
    Obsidian.opts.templates.folder = "templates"
    print("M.get_template_dir():", M.get_template_dir())

    local note = Note.create { dir = M.get_template_dir(), id = "zettel" }
    note:write()

    local spec = assert(M.load_template_customizations "zettel")

    eq(zettelConfig.notes_subdir, spec.notes_subdir)
    eq(zettelConfig.note_id_func, spec.note_id_func)
  end, nil, { templates = { folder = "templates" } })
end

T["substitute_template_variables()"]["should substitute built-in variables"] = function()
  h.with_tmp_client(function(client)
    local text = "today is {{date}} and the title of the note is {{title}}"
    eq(
      string.format("today is %s and the title of the note is %s", os.date "%Y-%m-%d", "FOO"),
      M.substitute_template_variables(text, tmp_template_context())
    )
  end)
end

T["substitute_template_variables()"]["should substitute custom variables"] = function()
  h.with_tmp_client(function(client)
    Obsidian.opts.templates.substitutions = {
      weekday = function()
        return "Monday"
      end,
    }
    local text = "today is {{weekday}}"
    eq("today is Monday", M.substitute_template_variables(text, tmp_template_context()))

    eq(1, vim.tbl_count(Obsidian.opts.templates.substitutions))
    eq("function", type(Obsidian.opts.templates.substitutions.weekday))
  end)
end

T["substitute_template_variables()"]["should substitute consecutive custom variables"] = function()
  h.with_tmp_client(function(client)
    Obsidian.opts.templates.substitutions = {
      value = function()
        return "VALUE"
      end,
    }
    local text = "{{value}} and then {{value}} and then {{value}}"
    eq("VALUE and then VALUE and then VALUE", M.substitute_template_variables(text, tmp_template_context()))
  end)
end

T["substitute_template_variables()"]["should provide substitution functions with template context"] = function()
  h.with_tmp_client(function(client)
    Obsidian.opts.templates.substitutions = {
      test_var = function(ctx)
        return tostring(ctx.template_name)
      end,
    }
    local text = "my template is: {{test_var}}"
    local ctx = tmp_template_context { template_name = "My Template.md" }
    eq("my template is: My Template.md", M.substitute_template_variables(text, ctx))
  end)
end

return T
