local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local Path = require "obsidian.path"
local helpers = require "tests.helpers"

local T = new_set {
  hooks = {
    post_case = function()
      pcall(function()
        require("obsidian.cache").shutdown()
      end)
      if Obsidian and Obsidian.dir then
        vim.fn.delete(tostring(Obsidian.dir), "rf")
      end
      Obsidian = nil
      require("obsidian.lsp.watchfiles").reset_handlers()
    end,
  },
}

T["quick switch"] = new_set()

T["quick switch"]["passes config to find notes"] = function()
  local captured
  Obsidian = {
    opts = {
      quick_switch = {
        show_existing_only = false,
        show_attachments = true,
      },
    },
    picker = {
      find_notes = function(opts)
        captured = opts
      end,
    },
  }

  require "obsidian.commands.quick_switch" { args = "foo" }

  eq("Quick Switch", captured.prompt_title)
  eq("foo", captured.query)
  eq(false, captured.show_existing_only)
  eq(true, captured.show_attachments)
end

T["quick switch"]["find notes passes options to find files"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  Obsidian = {
    dir = dir,
    opts = {
      picker = { note_mappings = {} },
    },
  }

  local picker = require "obsidian.picker"
  local original_find_files = picker.find_files
  local captured
  picker.find_files = function(opts)
    captured = opts
  end

  picker.find_notes {
    no_default_mappings = true,
    show_existing_only = false,
    show_attachments = true,
  }

  picker.find_files = original_find_files

  eq(false, captured.show_existing_only)
  eq(true, captured.show_attachments)
  eq(true, captured.use_cache)
end

T["quick switch"]["cache picker filters attachments and missing links"] = function()
  local dir = Path.temp { suffix = "-obsidian-cache" }
  dir:mkdir { parents = true }
  helpers.write("# Note\n[[Missing]]\n![[Image.png]]\n![[Missing.pdf]]", dir / "Note.md")
  helpers.write("attachment", dir / "Image.png")
  Obsidian = { dir = dir }

  local cache = require "obsidian.cache"
  cache.setup { enabled = true, backend = "memory" }
  vim.wait(1000, function()
    return cache.is_ready()
  end)

  local picker = require "obsidian.picker"
  local original_pick = picker.pick
  local entries
  picker.pick = function(values)
    entries = values
  end

  picker.find_files_from_cache { use_cache = true }
  local default_seen = {}
  for _, entry in ipairs(entries) do
    default_seen[entry.text] = true
  end
  eq(true, default_seen["Note.md"])
  eq(nil, default_seen["Image.png"])
  eq(nil, default_seen["Missing"])
  eq(nil, default_seen["Missing.pdf"])

  picker.find_files_from_cache { use_cache = true, show_existing_only = false }
  local missing_seen = {}
  for _, entry in ipairs(entries) do
    missing_seen[entry.text] = true
  end
  eq(true, missing_seen["Note.md"])
  eq(true, missing_seen["Missing"])
  eq(nil, missing_seen["Image.png"])
  eq(nil, missing_seen["Missing.pdf"])

  picker.find_files_from_cache { use_cache = true, show_existing_only = false, show_attachments = true }
  local attachment_seen = {}
  for _, entry in ipairs(entries) do
    attachment_seen[entry.text] = entry.user_data
  end
  eq({ attachment = false, missing = false }, attachment_seen["Note.md"])
  eq({ attachment = false, missing = true }, attachment_seen["Missing"])
  eq({ attachment = true, missing = false }, attachment_seen["Image.png"])
  eq({ attachment = true, missing = true }, attachment_seen["Missing.pdf"])

  picker.pick = original_pick
end

return T
