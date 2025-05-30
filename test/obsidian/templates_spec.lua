local get_tmp_client = require("test_utils").get_tmp_client
local cleanup_tmp_client = require("test_utils").cleanup_tmp_client
local Note = require "obsidian.note"
local templates = require "obsidian.templates"
local NewNotesLocation = require("obsidian.config").NewNotesLocation

local templates_dir = "templates"

--- @type obsidian.config.CustomTemplateOpts
local zettelConfig = {
  dir = "/custom/path/to/zettels",
  note_id_func = function()
    return "hummus"
  end,
}

describe("template", function()
  --- @type obsidian.Client|?
  local client = nil

  before_each(function()
    client = get_tmp_client("templates", templates_dir)
  end)

  after_each(function()
    if client then
      cleanup_tmp_client(client)
    end
  end)

  describe("templates.load_template_customizations()", function()
    before_each(function()
      client.opts.templates.customizations = {
        Zettel = zettelConfig,
      }
    end)

    after_each(function()
      client.opts.templates.customizations = nil
    end)

    it("should not load customizations for non-existant templates", function()
      -- Arrange
      local old_id_func = client.opts.note_id_func

      -- Act
      templates.load_template_customizations("zettel", client)

      -- Assert
      assert.falsy(client.opts.notes_subdir)
      assert.are_not.equal(zettelConfig.note_id_func, client.opts.note_id_func)
      assert.equal(old_id_func, client.opts.note_id_func)
    end)

    it("should load customizations for existing template", function()
      -- Arrange
      client:create_note { dir = templates_dir, id = "zettel" }

      -- Act
      templates.load_template_customizations("zettel", client)

      -- Assert
      assert.equal(zettelConfig.dir, client.opts.notes_subdir)
      assert.equal(zettelConfig.note_id_func, client.opts.note_id_func)
    end)

    it("should load customizations case-insensitively if template exists", function()
      -- Arrange
      client:create_note { dir = templates_dir, id = "zettel" }

      -- Act
      templates.load_template_customizations("zettel", client)

      -- Assert
      assert.equal(zettelConfig.dir, client.opts.notes_subdir)
      assert.equal(zettelConfig.note_id_func, client.opts.note_id_func)
    end)
  end)

  describe("templates.restore_client_configurations()", function()
    it("should do nothing if no configuration is cached", function()
      -- Arrange
      local old_id_func = client.opts.note_id_func
      local notes_subdir = client.opts.notes_subdir

      -- Act
      templates.restore_client_configurations(client)

      -- Assert
      assert.equal(old_id_func, client.opts.note_id_func)
      assert.equal(notes_subdir, client.opts.notes_subdir)
    end)

    it("should reload client configuration after successfully loading previously", function()
      -- Arrange
      client:create_note { dir = templates_dir, id = "zettel" }
      local old_id_func = client.opts.note_id_func
      local notes_subdir = client.opts.notes_subdir
      client.opts.templates.customizations = {
        Zettel = zettelConfig,
      }

      -- Act
      templates.load_template_customizations("zettel", client)
      assert.equal(zettelConfig.dir, client.opts.notes_subdir)
      assert.equal(NewNotesLocation.notes_subdir, client.opts.new_notes_location)
      assert.equal(zettelConfig.note_id_func, client.opts.note_id_func)
      templates.restore_client_configurations(client)

      -- Assert
      assert.equal(old_id_func, client.opts.note_id_func)
      assert.equal(NewNotesLocation.current_dir, client.opts.new_notes_location)
      assert.equal(notes_subdir, client.opts.notes_subdir)
    end)
  end)

  describe("templates.substitute_template_variables()", function()
    it("should substitute built-in variables", function()
      local text = "today is {{date}} and the title of the note is {{title}}"
      assert.equal(
        string.format("today is %s and the title of the note is %s", os.date "%Y-%m-%d", "FOO"),
        templates.substitute_template_variables(text, client, Note.new("FOO", { "FOO" }, {}))
      )
    end)

    it("should substitute custom variables", function()
      client.opts.templates.substitutions = {
        weekday = function()
          return "Monday"
        end,
      }
      local text = "today is {{weekday}}"
      assert.equal("today is Monday", templates.substitute_template_variables(text, client, Note.new("foo", {}, {})))

      -- Make sure the client opts has not been modified.
      assert.equal(1, vim.tbl_count(client.opts.templates.substitutions))
      assert.equal("function", type(client.opts.templates.substitutions.weekday))
    end)
  end)
end)
