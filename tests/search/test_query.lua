local Query = require "obsidian.search.query"
local Path = require "obsidian.path"
local h = require "tests.helpers"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local child = MiniTest.new_child_neovim()

local root

local T = new_set {
  hooks = {
    pre_case = function()
      root = Path.temp { suffix = "-query-search" }
      root:mkdir { parents = true }
      local meetings = root / "meetings"
      local personal = root / "personal"
      meetings:mkdir()
      personal:mkdir()
      h.write(
        table.concat({
          "---",
          "status: Draft",
          "duration: 3",
          "aliases: []",
          'empty_quotes: ""',
          "tags: [work]",
          "---",
          "# Weekly Meeting",
          "mix the flour today",
          "",
          "call Alice about HappyCat",
          "- [ ] email Bob",
          "- [x] publish notes",
          "",
          "```",
          "#hidden",
          "```",
        }, "\n"),
        root / "meetings" / "work.md"
      )
      h.write(
        table.concat({
          "---",
          "status: Published",
          "rating:",
          "---",
          "# Personal Meetup",
          "mix slowly",
          "flour tomorrow",
          "#friends",
          "",
          "## Plans",
          "bring dog treats",
          "",
          "## Other",
          "ask about cat food",
          "- [ ] call Carol",
          "~~~",
          "#alsohidden",
          "~~~",
          "Ärger über Überraschungen",
        }, "\n"),
        root / "personal" / "meetup.md"
      )
      h.write("old work notes", root / "archive.md")
      child.restart { "-u", "scripts/minimal_init.lua" }
      child.lua([[Obsidian = { dir = require("obsidian.path").new(...) }]], { tostring(root) })
      h.child_setup_cache(child)
    end,
    post_case = function()
      child.stop()
      vim.fn.delete(tostring(root), "rf")
    end,
  },
}

---@param query string
---@param opts table|nil
---@return obsidian.search.QueryResult[]
---@return string|nil
local function search_raw(query, opts)
  local result = h.child_await(
    child,
    ([[
require("obsidian.search.query").search(%q, %s, function(items, err)
  done { items = items, err = err }
end)
]]):format(query, vim.inspect(vim.tbl_extend("force", { root = tostring(root) }, opts or {}))),
    { desc = "query results" }
  )
  return result.items, result.err
end

---@param query string
---@param opts table|nil
---@return obsidian.search.QueryResult[]
local function search(query, opts)
  local results, err = search_raw(query, opts)
  assert(not err, err)
  return results
end

local function paths(query)
  return vim.tbl_map(function(result)
    return result.document.relative_path
  end, search(query))
end

T["parser"] = new_set()

T["parser"]["uses implicit AND before OR and supports negated groups"] = function()
  local ast = assert(Query.parse "meeting work OR meetup personal")
  eq("or", ast.kind)
  eq("and", ast.left.kind)
  eq("and", ast.right.kind)
  eq({ "meetings/work.md", "personal/meetup.md" }, paths "meeting work OR meetup personal")
  eq({ "meetings/work.md", "archive.md" }, paths "work -(old missing)")
  eq({ "meetings/work.md" }, paths "work -(old notes)")
end

T["parser"]["reports incomplete delimiters unless requested otherwise"] = function()
  local _, quote_error = Query.parse '"unfinished'
  local _, group_error = Query.parse "meeting (work OR personal"
  eq(true, quote_error ~= nil)
  eq(true, group_error ~= nil)
  eq("and", assert(Query.parse("meeting (work OR personal", { allow_incomplete = true })).kind)
  eq("scope", assert(Query.parse("file:", { allow_incomplete = true })).kind)
  local _, property_error = Query.parse 'line:[status:"Draft"'
  eq(true, property_error ~= nil)
end

T["parser"]["rejects regular expressions in every query context"] = function()
  for _, query in ipairs {
    "/HappyC.t/",
    "/[/",
    "/unfinished",
    "path:/work/",
    "content:/HappyCat/",
    "tag:/work/",
    "work OR /notes/",
    "-(work /notes/)",
    "[status:/Draft/]",
    "[/status/:Draft]",
    "line:[status:/Draft/]",
    "match-case:[/status/:Draft]",
    "match-case:(content:/HappyCat/)",
  } do
    for _, allow_incomplete in ipairs { false, true } do
      local ast, err = Query.parse(query, { allow_incomplete = allow_incomplete })
      eq(nil, ast)
      eq(true, err:find("Regular expressions are not supported", 1, true) ~= nil)
    end
  end
end

T["terms"] = new_set()

T["terms"]["matches words, phrases, OR, and negation"] = function()
  eq({ "meetings/work.md" }, paths "weekly meeting")
  eq({ "meetings/work.md" }, paths '"mix the flour"')
  eq({ "meetings/work.md", "archive.md", "personal/meetup.md" }, paths "work OR friends")
  eq({ "archive.md" }, paths "work -meeting")
end

T["terms"]["matches slashes and pattern characters literally in quoted text"] = function()
  local path = root / "literal.md"
  h.write(
    table.concat({
      "---",
      "url: https://example.com/docs",
      [[quote: 'they said "hello"']],
      "---",
      "/HappyC.t/",
      'they said "hello" to each other',
    }, "\n"),
    path
  )
  child.lua([[require("obsidian.cache").notes.refresh(...)]], { tostring(path) })

  eq({ "literal.md" }, paths 'content:"/HappyC.t/"')
  eq({}, paths 'content:"/HappyCat/"')
  eq({ "literal.md" }, paths '"they said \\"hello\\" to each other"')
  eq({ "literal.md" }, paths '[url:"https://example.com/docs"]')
  eq({ "literal.md" }, paths '[quote:"they said \\"hello\\""]')
  eq({ "meetings/work.md" }, paths 'path:"meetings/"')
  eq({ "meetings/work.md" }, paths "path:meetings/work")
end

T["terms"]["folds Unicode case for case-insensitive terms"] = function()
  eq({ "personal/meetup.md" }, paths "ärger")
  eq({}, paths "match-case:ärger")
  eq({ "personal/meetup.md" }, paths "ignore-case:ärger")
end

T["operators"] = new_set()

T["operators"]["matches file, path, content, and case scopes"] = function()
  eq({ "personal/meetup.md" }, paths "file:meetup")
  eq({ "meetings/work.md" }, paths 'path:"meetings/work"')
  eq({ "meetings/work.md" }, paths 'content:"HappyCat"')
  eq({ "meetings/work.md" }, paths 'content:"Alice about HappyCat"')
  eq({}, paths "match-case:happycat")
  eq({ "meetings/work.md" }, paths "match-case:HappyCat")
  eq({ "meetings/work.md" }, paths "ignore-case:happycat")
end

T["operators"]["matches exact tags outside code blocks"] = function()
  eq({ "meetings/work.md" }, paths "tag:#work")
  eq({ "personal/meetup.md" }, paths "tag:friends")
  eq({}, paths "tag:hidden")
  eq({}, paths "tag:alsohidden")
  eq({}, paths "tag:friend")
end

T["operators"]["keeps line, block, section, and task terms together"] = function()
  eq({ "meetings/work.md" }, paths "line:(mix flour)")
  eq({}, paths "line:(call publish)")
  eq({ "meetings/work.md" }, paths "block:(call publish)")
  eq({}, paths "section:(dog cat)")
  eq({ "personal/meetup.md" }, paths "section:(dog treats)")
  eq({ "meetings/work.md" }, paths "task-todo:email")
  eq({ "meetings/work.md" }, paths "task-done:publish")
  eq({ "personal/meetup.md" }, paths "task:call")
end

T["properties"] = new_set()

T["properties"]["matches existence, values, OR, null, and comparisons"] = function()
  eq({ "meetings/work.md", "personal/meetup.md" }, paths "[status]")
  eq({ "meetings/work.md" }, paths "[status:Draft]")
  eq({ "meetings/work.md", "personal/meetup.md" }, paths "[status:Draft OR Published]")
  eq({ "personal/meetup.md" }, paths "[rating:null]")
  eq({}, paths "[aliases:null]")
  eq({}, paths "[empty_quotes:null]")
  eq({ "meetings/work.md" }, paths "[duration:<5]")
  eq({}, paths "[duration:>5]")
end

T["results are ranked by match quality and then by path"] = function()
  eq({ "meetings/work.md", "archive.md" }, paths "work")
  local results = search "HappyCat"
  eq(11, results[1].line)
  eq(18, results[1].col)
  eq(26, results[1].end_col)
  eq("call Alice about HappyCat", results[1].context)
end

T["cache universe includes generic searchable files"] = function()
  local note_path = root / "note.md"
  local base_path = root / "catalog.base"
  local canvas_path = root / "board.canvas"
  local excalidraw_path = root / "drawing.excalidraw"
  h.write("needle in a note", note_path)
  h.write("filters: needle in a base", base_path)
  h.write('{"text":"needle in a canvas"}', canvas_path)
  h.write('{"text":"needle in an excalidraw drawing"}', excalidraw_path)
  h.write("needle in plain text", root / "ignored.txt")
  for _, path in ipairs { note_path, base_path, canvas_path, excalidraw_path } do
    child.lua([[require("obsidian.cache").notes.refresh(...)]], { tostring(path) })
  end

  eq(
    { "board.canvas", "catalog.base", "drawing.excalidraw", "note.md" },
    vim.tbl_map(function(result)
      return result.document.relative_path
    end, search "needle")
  )
  eq(
    { "note.md" },
    vim.tbl_map(function(result)
      return result.document.relative_path
    end, search("needle", { include_non_markdown = false }))
  )
end

T["reports unsupported regex through the search callback"] = function()
  local results, err = search_raw "content:/HappyCat/"
  eq({}, results)
  eq(true, err:find("Regular expressions are not supported", 1, true) ~= nil)
end

T["does not execute without the cache"] = function()
  child.lua [[require("obsidian.cache").shutdown()]]
  local results, err = search_raw "work"
  eq({}, results)
  eq(true, err:find("cache", 1, true) ~= nil)
end

T["metadata-only queries do not start ripgrep"] = function()
  child.lua [[
local Ripgrep = require "obsidian.search.ripgrep"
local original = Ripgrep.read_lines_async
_G.read_lines_calls = 0
Ripgrep.read_lines_async = function(...)
  _G.read_lines_calls = _G.read_lines_calls + 1
  return original(...)
end
]]

  local metadata_results = search "[status:Draft]"
  eq(
    { "meetings/work.md" },
    vim.tbl_map(function(result)
      return result.document.relative_path
    end, metadata_results)
  )
  eq(nil, metadata_results[1].context)
  eq(0, child.lua_get "read_lines_calls")
  eq({ "meetings/work.md" }, paths "content:HappyCat")
  eq(1, child.lua_get "read_lines_calls")
end

return T
