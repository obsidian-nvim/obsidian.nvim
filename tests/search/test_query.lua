local Query = require "obsidian.search.query"
local Path = require "obsidian.path"
local h = require "tests.helpers"

local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

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
        }, "\n"),
        root / "personal" / "meetup.md"
      )
      h.write("old work notes", root / "archive.md")
      Obsidian = { dir = root }
      local cache = require "obsidian.cache"
      cache.setup { enabled = true, backend = "memory" }
      h.wait(function()
        return cache.is_ready()
      end, { desc = "query cache" })
    end,
    post_case = function()
      require("obsidian.cache").shutdown()
      vim.fn.delete(tostring(root), "rf")
      Obsidian = nil
      require("obsidian.lsp.watchfiles").reset_handlers()
    end,
  },
}

---@param query string
---@param opts table|nil
---@return obsidian.search.QueryResult[]
local function search(query, opts)
  local results, query_error
  Query.search(query, vim.tbl_extend("force", { root = root }, opts or {}), function(items, err)
    results, query_error = items, err
  end)
  h.wait(function()
    return results ~= nil
  end, { desc = "query results" })
  assert(not query_error, query_error)
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
end

T["cache universe includes notes and canvases"] = function()
  local note_path = root / "note.md"
  local canvas_path = root / "board.canvas"
  h.write("needle in a note", note_path)
  h.write('{"text":"needle in a canvas"}', canvas_path)
  h.write("needle in plain text", root / "ignored.txt")
  local cache = require "obsidian.cache"
  cache.notes.refresh(tostring(note_path))
  cache.notes.refresh(tostring(canvas_path))

  eq(
    { "board.canvas", "note.md" },
    vim.tbl_map(function(result)
      return result.document.relative_path
    end, search "needle")
  )
end

T["does not execute without the cache"] = function()
  require("obsidian.cache").shutdown()
  local results, err
  Query.search("work", { root = root }, function(items, search_error)
    results, err = items, search_error
  end)
  eq({}, results)
  eq(true, err:find("cache", 1, true) ~= nil)
end

T["metadata-only queries do not start ripgrep"] = function()
  local Ripgrep = require "obsidian.search.ripgrep"
  local original = Ripgrep.read_lines_async
  local calls = 0
  Ripgrep.read_lines_async = function(...)
    calls = calls + 1
    return original(...)
  end

  local ok, err = pcall(function()
    eq({ "meetings/work.md" }, paths "[status:Draft]")
    eq(0, calls)
    eq({ "meetings/work.md" }, paths "content:HappyCat")
    eq(1, calls)
  end)
  Ripgrep.read_lines_async = original
  if not ok then
    error(err)
  end
end

return T
