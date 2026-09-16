local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local Feed = require "obsidian.remote-vault.adapters.feed"
local GitHub = require "obsidian.remote-vault.adapters.github"

local T = new_set()

T["GitHub adapter lists and fetches issues"] = function()
  local calls = {}
  local runner = function(args, callback)
    calls[#calls + 1] = args
    if args[3] == "list" then
      callback(nil, {
        {
          number = 42,
          title = "Fix the sync",
          url = "https://github.com/acme/notes/issues/42",
          createdAt = "2026-01-01T00:00:00Z",
          updatedAt = "2026-01-02T00:00:00Z",
          author = { login = "octo" },
          labels = { { name = "bug" } },
          assignees = { { login = "dev" } },
          state = "OPEN",
        },
      })
    else
      callback(nil, {
        number = 42,
        title = "Fix the sync",
        url = "https://github.com/acme/notes/issues/42",
        createdAt = "2026-01-01T00:00:00Z",
        updatedAt = "2026-01-02T00:00:00Z",
        author = { login = "octo" },
        labels = { { name = "bug" } },
        assignees = { { login = "dev" } },
        state = "OPEN",
        body = "Issue body",
        comments = {
          {
            author = { login = "reviewer" },
            createdAt = "2026-01-03T00:00:00Z",
            body = "A comment",
            url = "https://github.com/acme/notes/issues/42#issuecomment-1",
          },
        },
      })
    end
  end

  local vault = GitHub.new {
    path = vim.fn.tempname() .. "-github-vault",
    repo = "acme/notes",
    labels = { "bug" },
    runner = runner,
  }
  local list_err, summaries
  vault.list(nil, function(err, value)
    list_err, summaries = err, value
  end)
  eq(nil, list_err)
  eq("acme/notes#42", summaries[1].id)
  eq("2026-01-02T00:00:00Z", summaries[1].revision)
  eq(true, vim.list_contains(calls[1], "--label"))

  local fetch_err, resource
  vault.fetch(summaries[1], nil, function(err, value)
    fetch_err, resource = err, value
  end)
  eq(nil, fetch_err)
  eq("github", resource.metadata.provider)
  eq("acme/notes", resource.metadata.repository)
  eq({ "bug" }, resource.metadata.labels)
  eq({ "dev" }, resource.metadata.assignees)
  eq("# Fix the sync", resource.content[1])
  eq(true, vim.list_contains(resource.content, "## Comments"))
  eq("view", calls[2][3])
end

T["feed adapter maps a feed.nvim query"] = function()
  local query
  local db = {
    feeds = {
      ["https://example.test/feed.xml"] = { title = "Example feed" },
    },
    entry = {
      title = "An article",
      link = "https://example.test/article",
      time = 1767225600,
      author = "Writer",
      feed = "https://example.test/feed.xml",
    },
  }
  db["entry-1"] = db.entry
  function db:filter(value)
    query = value
    return { "entry-1" }
  end
  function db:get_tags()
    return { "unread", "tech" }
  end
  function db:get()
    return "<p>Stored feed content</p>"
  end

  local vault = Feed.new {
    path = vim.fn.tempname() .. "-feed-vault",
    db = db,
    query = "+unread #20",
  }
  local list_err, summaries
  vault.list(nil, function(err, value)
    list_err, summaries = err, value
  end)
  eq(nil, list_err)
  eq("+unread #20", query)
  eq("entry-1", summaries[1].id)
  eq(true, summaries[1].revision ~= nil)

  local fetch_err, resource
  vault.fetch(summaries[1], nil, function(err, value)
    fetch_err, resource = err, value
  end)
  eq(nil, fetch_err)
  eq("feed.nvim", resource.metadata.provider)
  eq("Example feed", resource.metadata.feed_title)
  eq({ "tech", "unread" }, resource.metadata.feed_tags)
  eq("# An article", resource.content[1])
  eq("<p>Stored feed content</p>", resource.content[#resource.content])
end

T["public module exposes built-in adapters"] = function()
  local remote = require "obsidian.remote-vault"
  eq(GitHub, remote.adapters.github)
  eq(Feed, remote.adapters.feed)
end

return T
