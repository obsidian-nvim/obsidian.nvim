local helpers = require "tests.helpers"
local Path = require "obsidian.path"

local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      local dir = Path.temp { suffix = "-obsidian" }
      dir:mkdir { parents = true }
      require("obsidian").setup {
        legacy_commands = false,
        workspaces = { {
          path = tostring(dir),
        } },
        log_level = vim.log.levels.WARN,
      }
    end,
    post_case = function()
      require("obsidian.core-plugins.canvas").stop_server()
      vim.fn.delete(tostring(Obsidian.dir), "rf")
    end,
  },
}

T["read_canvas"] = function()
  local canvas = require "obsidian.core-plugins.canvas"
  local path = Obsidian.dir / "Board.canvas"
  helpers.write(
    vim.json.encode {
      nodes = {
        { id = "a", type = "text", text = "Hello", x = 0, y = 0, width = 200, height = 100 },
        { id = "b", type = "file", file = "Note.md", x = 260, y = 0, width = 200, height = 100 },
      },
      edges = {
        { id = "e1", fromNode = "a", toNode = "b", toEnd = "arrow" },
      },
    },
    path
  )

  local data, err = canvas.read_canvas(path)
  MiniTest.expect.equality(nil, err)
  MiniTest.expect.equality("text", data.nodes[1].type)
  MiniTest.expect.equality("file", data.nodes[2].type)
  MiniTest.expect.equality("e1", data.edges[1].id)
end

T["read_canvas rejects invalid JSON Canvas"] = function()
  local canvas = require "obsidian.core-plugins.canvas"
  local path = Obsidian.dir / "Bad.canvas"
  helpers.write(vim.json.encode { nodes = { { type = "text" } }, edges = {} }, path)

  local data, err = canvas.read_canvas(path)
  MiniTest.expect.equality(nil, data)
  MiniTest.expect.equality("Node 1 must have a string id", err)
end

T["open_file starts server and opens URL"] = function()
  local canvas = require "obsidian.core-plugins.canvas"
  local path = Obsidian.dir / "Board.canvas"
  helpers.write(vim.json.encode { nodes = {}, edges = {} }, path)

  local opened
  local old_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  local ok, err = pcall(function()
    MiniTest.expect.equality(true, canvas.open_file(tostring(path)))
    MiniTest.expect.equality(true, opened:match "^http://127%.0%.0%.1:%d+/%?path=" ~= nil)
  end)

  canvas.stop_server()
  vim.ui.open = old_open
  if not ok then
    error(err)
  end
end

T["opening a canvas buffer opens web UI"] = function()
  local path = Obsidian.dir / "Board.canvas"
  helpers.write(vim.json.encode { nodes = {}, edges = {} }, path)

  local opened
  local old_open = vim.ui.open
  vim.ui.open = function(url)
    opened = url
  end

  local ok, err = pcall(function()
    vim.cmd.edit(vim.fn.fnameescape(tostring(path)))
    vim.wait(1000, function()
      return opened ~= nil
    end)
    MiniTest.expect.equality(true, opened:match "^http://127%.0%.0%.1:%d+/%?path=" ~= nil)
  end)

  require("obsidian.core-plugins.canvas").stop_server()
  vim.ui.open = old_open
  vim.cmd "enew!"
  if not ok then
    error(err)
  end
end

return T
