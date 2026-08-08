local Index = require "obsidian.search.index"
local Query = require "obsidian.search.query"
local h = require "tests.helpers"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local T = new_set()

local documents = {
  Index.from_lines("/vault/meetings/work.md", {
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
  }, { root = "/vault" }),
  Index.from_lines("/vault/personal/meetup.md", {
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
  }, { root = "/vault" }),
  Index.from_lines("/vault/archive.md", { "old work notes" }, { root = "/vault" }),
}

local function paths(query)
  return vim.tbl_map(function(result)
    return result.document.relative_path
  end, Query.search(documents, query))
end

T["exports supported scopes for completion consumers"] = function()
  eq({
    "block",
    "content",
    "file",
    "ignore-case",
    "line",
    "match-case",
    "path",
    "section",
    "tag",
    "task",
    "task-done",
    "task-todo",
  }, Query.scopes)
end

T["parser"] = new_set()

T["parser"]["uses implicit AND before OR and supports negated groups"] = function()
  local ast = assert(Query.parse "meeting work OR meetup personal")
  eq("or", ast.kind)
  eq("and", ast.left.kind)
  eq("and", ast.right.kind)

  eq({ "meetings/work.md", "archive.md" }, paths "work -(old missing)")
  eq({ "meetings/work.md" }, paths "work -(old notes)")
end

T["parser"]["reports incomplete delimiters unless requested otherwise"] = function()
  local _, quote_error = Query.parse '"unfinished'
  local _, group_error = Query.parse "meeting (work OR personal"
  eq(true, quote_error ~= nil)
  eq(true, group_error ~= nil)
  eq("and", assert(Query.parse("meeting (work OR personal", { allow_incomplete = true })).kind)
end

T["terms"] = new_set()

T["terms"]["matches words, phrases, regex, OR, and negation"] = function()
  eq({ "meetings/work.md" }, paths "weekly meeting")
  eq({ "meetings/work.md" }, paths '"mix the flour"')
  eq({ "meetings/work.md" }, paths "/HappyC.t/")
  eq({ "meetings/work.md", "archive.md", "personal/meetup.md" }, paths "work OR friends")
  eq({ "archive.md" }, paths "work -meeting")
end

T["operators"] = new_set()

T["operators"]["matches file, path, content, and case scopes"] = function()
  eq({ "personal/meetup.md" }, paths "file:meetup")
  eq({ "meetings/work.md" }, paths 'path:"meetings/work"')
  eq({ "meetings/work.md" }, paths 'content:"HappyCat"')
  eq({ "meetings/work.md" }, paths "content:/Alice about HappyCat/")
  eq({}, paths "match-case:happycat")
  eq({ "meetings/work.md" }, paths "match-case:HappyCat")
  eq({ "meetings/work.md" }, paths "ignore-case:happycat")
end

T["operators"]["matches exact tags outside code blocks"] = function()
  eq({ "meetings/work.md" }, paths "tag:#work")
  eq({ "personal/meetup.md" }, paths "tag:friends")
  eq({}, paths "tag:hidden")
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
  local results = Query.search(documents, "HappyCat")
  eq(11, results[1].line)
end

T["index_async indexes notes and canvases before returning"] = function()
  local Path = require "obsidian.path"
  local dir = Path.temp { suffix = "-query-search" }
  dir:mkdir { parents = true }
  vim.fn.writefile({ "needle in a note" }, tostring(dir / "note.md"))
  vim.fn.writefile({ '{"text":"needle in a canvas"}' }, tostring(dir / "board.canvas"))
  vim.fn.writefile({ "needle in plain text" }, tostring(dir / "ignored.txt"))

  local indexed
  Index.index_async(dir, {}, function(result)
    indexed = result
  end)
  h.wait(function()
    return indexed ~= nil
  end, { desc = "query document index" })
  eq(
    { "board.canvas", "note.md" },
    vim.tbl_map(function(document)
      return document.relative_path
    end, indexed)
  )
  eq(
    { "board.canvas", "note.md" },
    vim.tbl_map(function(result)
      return result.document.relative_path
    end, Query.search(indexed, "needle"))
  )

  vim.fn.delete(tostring(dir), "rf")
end

return T
