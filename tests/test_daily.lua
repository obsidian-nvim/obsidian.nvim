local h = dofile "tests/helpers.lua"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local M = require "obsidian.daily"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      _G.client = require("obsidian").setup {
        workspaces = { {
          path = tostring(dir),
        } },
      }
    end,
    post_case = function()
      vim.fn.delete(tostring(_G.client.dir), "rf")
    end,
  },
}

T["daily_note_path"] = new_set()

T["daily_note_path"]["should use the path stem as the ID"] = function()
  _G.client.opts.daily_notes.date_format = "%Y/%b/%Y-%m-%d"
  local path, id = M.daily_note_path(nil, _G.client.opts)
  assert(vim.endswith(tostring(path), tostring(os.date("%Y/%b/%Y-%m-%d.md", os.time()))))
  eq(id, os.date("%Y-%m-%d", os.time()))
end

T["daily_note_path"]["should be able to initialize a daily note"] = function()
  local note = M.today(_G.client.opts)
  eq(true, note.path ~= nil)
  eq(true, note:exists())
end

T["daily_note_path"]["should not add frontmatter for today when disabled"] = function()
  h.with_tmp_client(function()
    _G.client.opts.disable_frontmatter = true
    local new_note = M.today(_G.client.opts)

    local saved_note = Note.from_file(new_note.path)
    eq(false, saved_note.has_frontmatter)
  end)
end

T["daily_note_path"]["should not add frontmatter for yesterday when disabled"] = function()
  _G.client.opts.disable_frontmatter = true
  local new_note = M.yesterday(_G.client.opts)
  local saved_note = Note.from_file(new_note.path)
  eq(false, saved_note.has_frontmatter)
end

return T
