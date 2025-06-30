local NewNotesLocation = require("obsidian.config").NewNotesLocation

local h = dofile "tests/helpers.lua"
local new_set, eq, neq = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.no_equality
local M = require "obsidian.templates"
local Note = require "obsidian.note"
require "obsidian.client"

--- @type obsidian.config.CustomTemplateOpts
local zettelConfig = {
  dir = "/custom/path/to/zettels",
  note_id_func = function()
    return "hummus"
  end,
}

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
    partial_note = Note.new { id = "FOO", aliases = { "FOO" }, tags = {} },
  })
end

T["substitute_template_variables()"] = new_set()
T["load_template_customizations()"] = new_set()
T["restore_client_configurations()"] = new_set()

T["load_template_customizations()"]["should not load customizations for non-existent templates"] = function()
  h.with_tmp_client(function(client)
    client.opts.templates.customizations = {
      Zettel = zettelConfig,
    }
    local old_id_func = client.opts.note_id_func

    M.load_template_customizations("zettel", client)

    eq(client.opts.notes_subdir, nil)
    neq(zettelConfig.note_id_func, client.opts.note_id_func)
    eq(old_id_func, client.opts.note_id_func)
  end, nil, { templates = { folder = "templates" } })
end

T["load_template_customizations()"]["should load customizations for existing template"] = function()
  h.with_tmp_client(function(client)
    client.opts.templates.customizations = {
      Zettel = zettelConfig,
    }

    client:create_note { dir = client:templates_dir(), id = "zettel" }

    M.load_template_customizations("zettel", client)

    eq(zettelConfig.dir, client.opts.notes_subdir)
    eq(zettelConfig.note_id_func, client.opts.note_id_func)
  end, nil, { templates = { folder = "templates" } })
end

T["restore_client_configurations()"]["should do nothing if no configuration is cached"] = function()
  h.with_tmp_client(function(client)
    local old_id_func = client.opts.note_id_func
    local notes_subdir = client.opts.notes_subdir

    M.restore_client_configurations(client)

    eq(old_id_func, client.opts.note_id_func)
    eq(notes_subdir, client.opts.notes_subdir)
  end)
end

T["restore_client_configurations()"]["should reload client configuration after successfully loading previously"] = function()
  h.with_tmp_client(function(client)
    client:create_note { dir = client:templates_dir(), id = "zettel" }
    local old_id_func = client.opts.note_id_func
    local notes_subdir = client.opts.notes_subdir
    client.opts.templates.customizations = {
      Zettel = zettelConfig,
    }

    M.load_template_customizations("zettel", client)
    eq(zettelConfig.dir, client.opts.notes_subdir)
    eq(NewNotesLocation.notes_subdir, client.opts.new_notes_location)
    eq(zettelConfig.note_id_func, client.opts.note_id_func)

    M.restore_client_configurations(client)

    eq(old_id_func, client.opts.note_id_func)
    eq(NewNotesLocation.current_dir, client.opts.new_notes_location)
    eq(notes_subdir, client.opts.notes_subdir)
  end, nil, { templates = { folder = "templates" } })
end

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
