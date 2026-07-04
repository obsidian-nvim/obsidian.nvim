local eq = MiniTest.expect.equality

local Path = require "obsidian.path"
local h = dofile "tests/helpers.lua"

local T, child = h.child_vault()

local function setup_vault(files)
  local dir = child.Obsidian.dir
  for rel, content in pairs(files) do
    local path = dir / rel
    Path.new(vim.fs.dirname(tostring(path))):mkdir { parents = true }
    h.write(content, path)
  end

  child.lua [[require("obsidian.cache").setup { enabled = true, backend = "memory" }]]
  h.child_wait(child, [[return require("obsidian.cache").is_ready()]], { desc = "cache ready" })

  return dir
end

T["registered as generic code action"] = function()
  setup_vault {
    ["Project.md"] = "# Project",
    ["Doc.md"] = "Project",
  }

  eq(
    { "Link unlinked mention", "obsidian.link_suggestion", true },
    child.lua [[
      local action = require("obsidian.lsp.handlers._code_action").actions.link_suggestion
      return { action.title, action.command.command, action.data.cond() }
    ]]
  )
end

T["opens picker with all suggestions and links selected mention"] = function()
  local dir = setup_vault {
    ["Project.md"] = "# Project",
    ["folder/Space.md"] = "---\naliases: [Rocket Ship]\n---\n# Space",
    ["Doc.md"] = "Project and rocket ship",
  }

  child.cmd("edit " .. vim.fn.fnameescape(tostring(dir / "Doc.md")))
  child.lua [[
    _G.pick_seen = {}
    Obsidian.picker.pick = function(entries, opts)
      _G.pick_seen = {
        prompt_title = opts.prompt_title,
        count = #entries,
        first = opts.format_item(entries[1]),
        second = opts.format_item(entries[2]),
      }
      opts.callback(entries[2])
    end
  ]]

  child.lua [[require("obsidian.actions").link_suggestion()]]

  eq({
    prompt_title = "Unlinked mentions",
    count = 2,
    first = "Project -> [[Project]]",
    second = "rocket ship -> [[folder/Space|rocket ship]]",
  }, child.lua_get "pick_seen")
  eq({ "Project and [[folder/Space|rocket ship]]" }, child.api.nvim_buf_get_lines(0, 0, -1, false))
end

T["picker selection links CJK mention"] = function()
  local dir = setup_vault {
    ["中文.md"] = "# 中文",
    ["Doc.md"] = "我喜欢中文历史",
  }

  child.cmd("edit " .. vim.fn.fnameescape(tostring(dir / "Doc.md")))
  child.lua [[
    _G.pick_seen = {}
    Obsidian.picker.pick = function(entries, opts)
      _G.pick_seen = {
        count = #entries,
        first = opts.format_item(entries[1]),
      }
      opts.callback(entries[1])
    end
  ]]

  child.lua [[require("obsidian.actions").link_suggestion()]]

  eq({ count = 1, first = "中文 -> [[中文]]" }, child.lua_get "pick_seen")
  eq({ "我喜欢[[中文]]历史" }, child.api.nvim_buf_get_lines(0, 0, -1, false))
end

return T
