local obsidian = require "obsidian"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local subst = require "obsidian.subst"

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

describe("subst.substitute_template_variables()", function()
  it("should substitute built-in variables", function()
    local client = tmp_client()
    local text = "today is {{date}} and the title of the note is {{title}}"
    MiniTest.expect.equality(
      string.format("today is %s and the title of the note is %s", os.date "%Y-%m-%d", "FOO"),
      subst.substitute_template_variables(text, {
        action = "clone_template",
        client = client,
        target_note = Note.new("FOO", { "FOO" }, {}),
      })
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
<<<<<<<< HEAD:tests/subst_spec.lua
    assert.equal(
      "today is Monday",
      subst.substitute_template_variables(text, {
        action = "clone_template",
        client = client,
        target_note = Note.new("foo", {}, {}),
      })
========
    MiniTest.expect.equality(
      "today is Monday",
      templates.substitute_template_variables(text, client, Note.new("foo", {}, {}))
>>>>>>>> main:tests/test_templates.lua
    )

    -- Make sure the client opts has not been modified.
    MiniTest.expect.equality(1, vim.tbl_count(client.opts.templates.substitutions))
    MiniTest.expect.equality("function", type(client.opts.templates.substitutions.weekday))
  end)
end)
