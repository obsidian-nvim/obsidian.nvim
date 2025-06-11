local obsidian = require "obsidian"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local templates = require "obsidian.templates"

---Get a client in a temporary directory.
---
---@return obsidian.Client
local tmp_client = function()
  -- This gives us a tmp file name, but we really want a directory.
  -- So we delete that file immediately.
  local tmpname = os.tmpname()
  os.remove(tmpname)

  local dir = Path:new(tmpname .. "-obsidian/")
  dir:mkdir { parents = true }

  return obsidian.new_from_dir(tostring(dir))
end

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

describe("templates.substitute_template_variables()", function()
  it("should substitute built-in variables", function()
    local client = tmp_client()
    local text = "today is {{date}} and the title of the note is {{title}}"
    MiniTest.expect.equality(
      string.format("today is %s and the title of the note is %s", os.date "%Y-%m-%d", "FOO"),
      templates.substitute_template_variables(text, tmp_template_context(client))
    )
  end)

  it("should substitute custom variables", function()
    local client = tmp_client()
    client.opts.templates.substitutions = {
      weekday = function()
        return "Monday"
      end,
    }
    local text = "today is {{weekday}}"
    MiniTest.expect.equality(
      "today is Monday",
      templates.substitute_template_variables(text, tmp_template_context(client))
    )

    -- Make sure the client opts has not been modified.
    MiniTest.expect.equality(1, vim.tbl_count(client.opts.templates.substitutions))
    MiniTest.expect.equality("function", type(client.opts.templates.substitutions.weekday))
  end)

  it("should provide substitution functions with template context", function()
    local client = tmp_client()
    client.opts.templates.substitutions = {
      test_var = function(ctx)
        return tostring(ctx.template_name)
      end,
    }
    local text = "my template is: {{test_var}}"
    local ctx = tmp_template_context(client, { template_name = "My Template.md" })
    MiniTest.expect.equality("my template is: My Template.md", templates.substitute_template_variables(text, ctx))
  end)
end)
