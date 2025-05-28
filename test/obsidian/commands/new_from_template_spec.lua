local get_tmp_client = require("test_utils").get_tmp_client
local cleanup_tmp_client = require("test_utils").cleanup_tmp_client
local new_from_template = require "obsidian.commands.new_from_template"
local spy = require "luassert.spy"

local templates_dir = "templates"

--- @type obsidian.config.CustomTemplateOpts
local zettelConfig = {
  dir = "31 Atomic",
  note_id_func = function(title)
    return "31.01 - " .. title
  end,
}

describe("new_from_template", function()
  --- @type obsidian.Client
  local client = nil

  before_each(function()
    client = get_tmp_client("new_from_template", templates_dir)
    vim.loop.fs_mkdir(tostring(client.dir) .. "/" .. zettelConfig.dir, 448)
    client.picker = function(_)
      return {
        find_templates = function(_, opts)
          opts.callback()
        end,
      }
    end
    client.opts.templates.customizations = {
      Zettel = zettelConfig,
    }
    client.opts.new_notes_location = "notes_subdir"
  end)

  after_each(function()
    if client then
      cleanup_tmp_client(client)
    end
  end)

  it("should always try to load and restore template configurations", function()
    -- Arrange
    local templates = require "obsidian.templates"
    client:create_note { dir = templates_dir, id = "zettel" }
    spy.on(templates, "load_template_customizations")
    spy.on(templates, "restore_client_configurations")

    -- Act
    ---@diagnostic disable-next-line: missing-fields
    new_from_template(client, { fargs = { "Special Title", "Zettel" } })

    -- Assert
    assert.spy(templates.load_template_customizations).was.called()
    assert.spy(templates.restore_client_configurations).was.called()
  end)

  it("should place matched templates in the custom directory", function()
    -- Arrange
    client:create_note { dir = templates_dir, id = "zettel" }
    local expectedDir = client.dir / zettelConfig.dir
    local title = "The Big Bang"
    local id = zettelConfig.note_id_func(title)
    local expected = string.format("%s/%s.md", expectedDir, id)
    client.picker = function(_)
      return {
        find_templates = function(_, opts)
          opts.callback "zettel"
        end,
      }
    end

    -- Act
    ---@diagnostic disable-next-line: missing-fields

    -- Must pass path here because we mock the fuzzy finder
    new_from_template(client, { fargs = { title, "Zettel" } })
    local f = io.open(expected, "r")

    -- Assert
    assert.truthy(f)
    io.close(f)
  end)
end)
