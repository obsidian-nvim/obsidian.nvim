local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function open_source(contents, extra)
  local files = h.mock_vault_contents(
    child.Obsidian.dir,
    vim.tbl_extend("force", {
      ["source.md"] = contents,
    }, extra or {})
  )
  child.cmd("edit " .. vim.fn.fnameescape(files["source.md"]))
  child.lua [[vim.b.obsidian_buffer = true]]
  return files
end

T["links the word under cursor to an existing note"] = function()
  local files = open_source("Open target now", { ["target.md"] = "# Target" })
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  child.lua(([[
    require("obsidian.picker").find_notes = function(opts)
      opts.callback { %q }
    end
    require("obsidian.actions").link()
  ]]):format(files["target.md"]))

  eq("Open [[target]] now", child.api.nvim_get_current_line())
end

T["creates and links a note from the word under cursor"] = function()
  open_source "Make Fresh now"
  child.api.nvim_win_set_cursor(0, { 1, 7 })

  child.lua [[require("obsidian.actions").link_new()]]

  eq(true, child.api.nvim_get_current_line():match "^Make %[%[%d+%-[A-Z]+|Fresh%]%] now$" ~= nil)
end

T["uses an explicit visual range from a code action"] = function()
  local files = open_source("first target last", { ["target.md"] = "# Target" })
  child.api.nvim_win_set_cursor(0, { 1, 1 })

  child.lua(([[
    require("obsidian.picker").find_notes = function(opts)
      opts.callback { %q }
    end
    require("obsidian.actions").link({
      start = { line = 0, character = 6 },
      ["end"] = { line = 0, character = 12 },
    }, 0)
  ]]):format(files["target.md"]))

  eq("first [[target]] last", child.api.nvim_get_current_line())
end

T["creates a note from an explicit code action range"] = function()
  open_source "first Fresh last"
  child.api.nvim_win_set_cursor(0, { 1, 1 })

  child.lua [[
    require("obsidian.actions").link_new({
      start = { line = 0, character = 6 },
      ["end"] = { line = 0, character = 11 },
    }, 0)
  ]]

  eq(true, child.api.nvim_get_current_line():match "^first %[%[%d+%-[A-Z]+|Fresh%]%] last$" ~= nil)
end

T["keeps UTF-8 word ranges intact"] = function()
  local files = open_source("See Привет now", { ["привет.md"] = "# Привет" })
  child.api.nvim_win_set_cursor(0, { 1, 6 })

  child.lua(([[
    require("obsidian.picker").find_notes = function(opts)
      opts.callback { %q }
    end
    require("obsidian.actions").link()
  ]]):format(files["привет.md"]))

  eq("See [[привет|Привет]] now", child.api.nvim_get_current_line())
end

return T
