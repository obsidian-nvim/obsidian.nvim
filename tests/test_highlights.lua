local h = dofile "tests/helpers.lua"
local Document = require "obsidian.parse.document"
local highlights = require "obsidian.highlights"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

T["find parses multiline input and applies Document exclusions"] = function()
  local lines = {
    "---",
    "title: ==frontmatter==",
    "---",
    "==body== and ==next==",
    "before `code",
    "==span==` after",
    "```",
    "==fenced==",
    "```",
    "",
    "    ==indented==",
    "",
    "<!-- ==html== -->",
    "%% ==obsidian== %%",
    "==a=b==",
  }
  local document = Document.parse(lines)
  local matches = highlights.find(lines, { document = document })

  eq(
    {
      { text = "body", row = 3, col = 0 },
      { text = "next", row = 3, col = 13 },
      { text = "a=b", row = 14, col = 0 },
    },
    vim.tbl_map(function(match)
      return {
        text = match.text,
        row = match.range.start_row,
        col = match.range.start_col,
      }
    end, matches)
  )
end

local child
T["find_vault_async"], child = h.child_vault()

T["find_vault_async"]["finds parsed highlights across markdown files"] = function()
  h.child_mock_vault_contents(child, {
    ["a.md"] = "==first==\n```\n==code==\n```",
    ["frontmatter.md"] = "---\ntitle: ==hidden==\n---",
    ["nested/c.qmd"] = "é ==第二== and ==x=y==",
    ["templates/ignored.md"] = "==template==",
    ["ignored.txt"] = "==text==",
  })

  local result = h.child_await(
    child,
    [[
    require("obsidian.highlights").find_vault_async(function(matches)
      done(vim.tbl_map(function(match)
        return {
          file = vim.fs.basename(match.filename),
          text = match.text,
          line = match.lnum,
          col = match.col,
        }
      end, matches))
    end)
  ]]
  )

  eq({
    { file = "a.md", text = "first", line = 1, col = 1 },
    { file = "c.qmd", text = "第二", line = 1, col = 4 },
    { file = "c.qmd", text = "x=y", line = 1, col = 19 },
  }, result)
end

T["find_vault_async"]["command searches the vault by default"] = function()
  h.child_mock_vault_contents(child, { ["a.md"] = "==first==" })

  local result = h.child_await(
    child,
    [[
    require("obsidian.picker").select = function(items, opts)
      done({ count = #items, label = opts.format_item(items[1]) })
    end
    require("obsidian.commands.highlights")({ args = "" })
  ]]
  )

  eq({ count = 1, label = "a.md:1:1  first" }, result)
end

T["find_vault_async"]["command searches only the current note for percent"] = function()
  local files = h.child_mock_vault_contents(child, {
    ["current.md"] = "---\ntitle: ==hidden==\n---\n==current==",
    ["other.md"] = "==other==",
  })
  child.cmd("edit " .. vim.fn.fnameescape(files["current.md"]))

  child.lua [[
    require("obsidian.picker").select = function(items, opts)
      _G.highlight_picker_result = { count = #items, label = opts.format_item(items[1]) }
    end
    require("obsidian.commands.highlights")({ args = "%" })
  ]]

  eq({ count = 1, label = "4:1  current" }, child.lua_get "highlight_picker_result")
end

return T
