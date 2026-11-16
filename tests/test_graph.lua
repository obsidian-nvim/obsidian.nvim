local helpers = require "tests.helpers"
local T, child = helpers.child_vault {
  pre_case = [[
    local cache = require "obsidian.cache"
    cache.setup { enabled = true, backend = "memory" }
    assert(vim.wait(3000, cache.is_ready, 10), "cache not ready")
    _G.Graph = require "obsidian.graph"
    _G.eq = MiniTest.expect.equality
    _G.put = function(rel, row)
      row.path = tostring(Obsidian.dir / rel)
      cache.notes.upsert(row)
      return row.path
    end
    _G.write = function(rel, lines)
      local path = tostring(Obsidian.dir / rel)
      vim.fn.mkdir(vim.fs.dirname(path), "p")
      vim.fn.writefile(type(lines) == "table" and lines or { lines }, path)
      return path
    end
    _G.scan = function()
      local graph, err, done
      Graph.from_vault_async(function(value, error_message)
        graph, err, done = value, error_message, true
      end, { dir = Obsidian.dir })
      assert(vim.wait(3000, function() return done end, 10), "graph scan timed out")
      assert(graph, err)
      return graph
    end
  ]],
  post_case = [[require("obsidian.cache").shutdown()]],
}

T["builds deterministic note graph and diagnostics"] = function()
  child.lua [=[
    local a = put("A.md", { links_out = {
      { kind = "wiki", raw = "[[Project B]]", target = "Project B", line = 1, col = 1 },
      { kind = "wiki", raw = "[[Missing]]", target = "Missing", line = 2, col = 1 },
      { kind = "wiki", raw = "[[Missing.md]]", target = "Missing.md", line = 3, col = 1 },
      { kind = "markdown", target = "https://example.com" },
    } })
    local b = put("nested/B.md", { id = "project-b", aliases = { "Project B" }, properties = { title = "Better B" } })
    local orphan = put("Orphan.md", {})
    local graph = Graph.from_cache()
    local result = graph:to_table()
    eq({
      { id = "missing:note:Missing.md", type = "missing", title = "Missing", folder = "", aliases = {}, tags = {}, exists = false },
      { id = "note:A.md", type = "note", title = "A", path = a, folder = "", aliases = {}, tags = {}, exists = true },
      { id = "note:Orphan.md", type = "note", title = "Orphan", path = orphan, folder = "", aliases = {}, tags = {}, exists = true },
      { id = "note:nested/B.md", type = "note", title = "Better B", path = b, folder = "nested", aliases = { "Project B" }, tags = {}, exists = true },
    }, result.nodes)
    eq({
      { source = "note:A.md", target = "missing:note:Missing.md" },
      { source = "note:A.md", target = "note:nested/B.md" },
    }, result.links)
    eq({ source = "note:A.md", path = a, target = "Missing", kind = "wiki", raw = "[[Missing]]", line = 2, col = 1 }, graph:broken_links()[1])
    eq(2, #graph:broken_links())
    eq({}, graph:ambiguous_links())
    eq({ orphan }, graph:orphan_files())
  ]=]
end

T["retains extensions and separates node namespaces"] = function()
  child.lua [=[
    put("A.md", {})
    put("A.base", {})
    put("A.qmd", {})
    put("tag:graph.md", { tags = { "graph" } })
    put("missing:note:Missing.md", {})
    put("Source.md", { links_out = {
      { kind = "wiki", target = "A.base" },
      { kind = "wiki", target = "A.md" },
      { kind = "wiki", target = "A.qmd" },
      { kind = "wiki", target = "Missing" },
    } })
    local result = Graph.from_cache():to_table { include_tag_nodes = true }
    local ids = {}
    for _, node in ipairs(result.nodes) do
      assert(not ids[node.id], "duplicate identity")
      ids[node.id] = node.type
    end
    eq(8, #result.nodes)
    eq("note", ids["note:A.base"])
    eq("note", ids["note:tag:graph.md"])
    eq("tag", ids["tag:graph"])
    eq("missing", ids["missing:note:Missing.md"])
    eq(5, #result.links)
  ]=]
end

T["exact paths beat conflicting aliases and basename references"] = function()
  child.lua [=[
    put("A.md", { links_out = { { kind = "wiki", target = "B" } } })
    put("B.md", {})
    put("other/B.md", {})
    put("Other.md", { aliases = { "B" } })
    local graph = Graph.from_cache()
    eq({ { source = "note:A.md", target = "note:B.md" } }, graph:to_table().links)
    eq({}, graph:broken_links())
    eq({}, graph:ambiguous_links())
  ]=]
end

T["resolves source-relative wiki and markdown paths before root paths"] = function()
  child.lua [=[
    put("folder/A.md", { links_out = {
      { kind = "wiki", target = "B" },
      { kind = "markdown", target = "./B.md" },
      { kind = "markdown", target = "../Root.md" },
      { kind = "wiki", target = "/B.md" },
    } })
    put("folder/B.md", {})
    put("B.md", {})
    put("Root.md", {})
    local graph = Graph.from_cache()
    eq({
      { source = "note:folder/A.md", target = "note:B.md" },
      { source = "note:folder/A.md", target = "note:Root.md" },
      { source = "note:folder/A.md", target = "note:folder/B.md" },
    }, graph:to_table().links)
    eq({}, graph:broken_links())
    eq({}, graph:ambiguous_links())
  ]=]
end

T["explicit paths do not fall back and traversal cannot escape the vault"] = function()
  child.lua [=[
    put("folder/A.md", { links_out = {
      { kind = "wiki", target = "./B.md" },
      { kind = "markdown", target = "../../B.md" },
    } })
    put("B.md", {})
    local graph = Graph.from_cache()
    eq(1, #graph:broken_links())
    eq("./B.md", graph:broken_links()[1].target)
    eq({ { source = "note:folder/A.md", target = "missing:note:folder/B.md" } }, graph:to_table().links)
  ]=]
end

T["reports ambiguous symbols separately from missing links"] = function()
  child.lua [=[
    put("Source.md", { links_out = { { kind = "wiki", target = "Shared" } } })
    put("one/A.md", { aliases = { "Shared" } })
    put("two/B.md", { aliases = { "Shared" } })
    local graph = Graph.from_cache()
    eq({}, graph:broken_links())
    eq({ "note:one/A.md", "note:two/B.md" }, graph:ambiguous_links()[1].candidates)
    eq({}, graph:to_table().links)
    eq(3, #graph:to_table().nodes)
  ]=]
end

T["case-exact paths win and case-folded collisions stay ambiguous"] = function()
  child.lua [=[
    put("Source.md", { links_out = {
      { kind = "wiki", target = "Case.md" },
      { kind = "wiki", target = "CASE.md" },
    } })
    put("Case.md", {})
    put("case.md", {})
    local graph = Graph.from_cache()
    eq({ { source = "note:Source.md", target = "note:Case.md" } }, graph:to_table().links)
    eq({ "note:Case.md", "note:case.md" }, graph:ambiguous_links()[1].candidates)
    eq({}, graph:broken_links())
  ]=]
end

T["requires explicit base extensions and distinguishes multiple note formats"] = function()
  child.lua [=[
    put("Source.md", { links_out = {
      { kind = "wiki", target = "Base" },
      { kind = "wiki", target = "Base.base" },
      { kind = "wiki", target = "Multi" },
    } })
    put("Base.base", {})
    put("Multi.md", {})
    put("Multi.qmd", {})
    local graph = Graph.from_cache()
    eq("Base", graph:broken_links()[1].target)
    eq({ "note:Multi.md", "note:Multi.qmd" }, graph:ambiguous_links()[1].candidates)
    eq("note:Base.base", graph:to_table().links[2].target)
  ]=]
end

T["normalizes and deduplicates tags including nested and Unicode tags"] = function()
  child.lua [=[
    local tagged = put("Tagged.md", { tags = { "Graph", "#graph", "#Health/Status", "É", "é", "#" } })
    local plain = put("Plain.md", {})
    local graph = Graph.from_cache()
    eq({ plain, tagged }, graph:orphan_files())
    eq({ plain }, graph:orphan_files { include_tag_nodes = true })
    eq({}, graph:to_table().links)
    eq({
      { source = "note:Tagged.md", target = "tag:graph" },
      { source = "note:Tagged.md", target = "tag:health/status" },
      { source = "note:Tagged.md", target = "tag:é" },
    }, graph:to_table { include_tag_nodes = true }.links)
    eq(5, #graph:to_table { include_tag_nodes = true }.nodes)
  ]=]
end

T["includes attachments and checks missing attachment references"] = function()
  child.lua [=[
    Obsidian.opts.attachments.folder = "assets"
    local image = write("assets/image.png", "image")
    local unused = write("assets/unused.pdf", "pdf")
    require("obsidian.cache").notes.refresh(image)
    require("obsidian.cache").notes.refresh(unused)
    put("Source.md", { links_out = {
      { kind = "wiki", target = "image.png", embed = true },
      { kind = "markdown", target = "assets/image.png" },
      { kind = "wiki", target = "missing.png", embed = true },
      { kind = "wiki", target = "unsupported.txt" },
    } })
    local graph = Graph.from_cache()
    eq({
      { source = "note:Source.md", target = "attachment:assets/image.png" },
      { source = "note:Source.md", target = "missing:attachment:assets/missing.png" },
    }, graph:to_table().links)
    eq("attachment", graph:to_table().nodes[1].type)
    eq("image.png", graph:to_table().nodes[1].title)
    eq("missing.png", graph:broken_links()[1].target)
    eq(1, #graph:broken_links())
    eq({}, graph:orphan_files())
    eq({ unused }, graph:orphan_files { include_attachments = true })
  ]=]
end

T["resolves source-relative attachment folders and URL-encoded targets"] = function()
  child.lua [=[
    Obsidian.opts.attachments.folder = "./assets"
    local image = write("folder/assets/my image.png", "image")
    require("obsidian.cache").notes.refresh(image)
    put("folder/A.md", { links_out = {
      { kind = "wiki", target = "my%20image.png" },
      { kind = "markdown", target = "<assets/my%20image.png>" },
      { kind = "markdown", target = "<https://example.com>" },
    } })
    local graph = Graph.from_cache()
    eq({ { source = "note:folder/A.md", target = "attachment:folder/assets/my image.png" } }, graph:to_table().links)
    eq({}, graph:broken_links())
  ]=]
end

T["reports duplicate attachment names and paths as ambiguous"] = function()
  child.lua [=[
    Obsidian.opts.attachments.folder = "assets"
    for _, rel in ipairs { "one/image.png", "two/image.png", "folder/assets/file.pdf", "assets/file.pdf" } do
      require("obsidian.cache").notes.refresh(write(rel, "asset"))
    end
    put("folder/A.md", { links_out = {
      { kind = "wiki", target = "image.png" },
      { kind = "markdown", target = "assets/file.pdf" },
    } })
    local graph = Graph.from_cache()
    eq({}, graph:broken_links())
    eq(2, #graph:ambiguous_links())
    eq({}, graph:to_table().links)
    eq({ "attachment:one/image.png", "attachment:two/image.png" }, graph:ambiguous_links()[2].candidates)
  ]=]
end

T["detaches inputs, exports and all diagnostic results"] = function()
  child.lua [=[
    local first = put("First.md", { tags = { "graph" }, aliases = { "First alias" }, links_out = {
      { kind = "wiki", target = "Missing" },
      { kind = "wiki", target = "Shared" },
    } })
    put("A.md", { aliases = { "Shared" } })
    put("B.md", { aliases = { "Shared" } })
    local graph = Graph.from_cache()
    local cache = require "obsidian.cache"
    cache.notes.get(first).links_out[1].target = "Changed"
    cache.notes.get(first).tags[1] = "changed"
    put("Later.md", {})
    local before = graph:to_table { include_tag_nodes = true }
    local exported = graph:to_table { include_tag_nodes = true }
    for _, node in ipairs(exported.nodes) do
      node.tags[1], node.aliases[1] = "", "mutated"
    end
    exported.links[1].target = "changed"
    graph:broken_links()[1].target = "changed"
    graph:ambiguous_links()[1].candidates[1] = "changed"
    graph:orphan_files()[1] = "changed"
    eq(before, graph:to_table { include_tag_nodes = true })
    eq("Missing", graph:broken_links()[1].target)
    eq({ "note:A.md", "note:B.md" }, graph:ambiguous_links()[1].candidates)
    eq(4, #graph:to_table().nodes)
    eq(5, #Graph.from_cache():to_table().nodes)
    assert(vim.tbl_contains(graph:orphan_files(), first))
  ]=]
end

T["cache constructor performs no filesystem reads"] = function()
  child.lua [=[
    put("A.md", {})
    local original = io.open
    io.open = function() error("unexpected filesystem read") end
    local ok, graph = pcall(Graph.from_cache)
    io.open = original
    assert(ok, graph)
    eq(1, #graph:to_table().nodes)
  ]=]
end

T["rg and cache snapshots agree on full-note metadata and inventory"] = function()
  child.lua [=[
    assert(vim.fn.executable "rg" == 1, "rg is required for this test")
    Obsidian.opts.attachments.folder = "assets"
    Obsidian.opts.file.ignore_filters = { "skip/**" }
    Obsidian.opts.search.max_lines = 2
    require("obsidian.ignore").clear_cache()
    write(".gitignore", "gitignored.md")
    write(".git/ignored.md", "[[No]]")
    write(".obsidian/ignored.md", "[[No]]")
    write("skip/ignored.md", "[[No]]")
    write(".hidden.md", "#hidden")
    write("gitignored.md", "#included")
    write("templates/Template.md", "#template")
    write("formats/Note.markdown", "[[Target]]")
    write("formats/Note.qmd", "[[Target]]")
    write("formats/Note.base", "filters: []")
    write("Isolated.md", "No links or tags")
    write("assets/image.png", "image")
    write("Target.md", { "---", "aliases: [Destination]", "tags: [Graph]", "---", "# Target" })
    local lines = { "---", "tags: [Graph, Health/Status]", "---", "```", "[[Not a link]] #excluded", "```", "<!-- [[Comment]] -->" }
    for _ = 1, 50 do lines[#lines + 1] = "padding" end
    lines[#lines + 1] = "[[Destination#Heading]] ![[image.png]] #inline"
    lines[#lines + 1] = "[[Absent]] ![[absent.pdf]]"
    write("Source.md", lines)
    local cache = require "obsidian.cache"
    cache.notes.reindex()
    local cached = Graph.from_cache()
    cache.shutdown()
    local graph = scan()
    eq(false, cache.is_enabled())
    eq(cached:to_table { include_tag_nodes = true }, graph:to_table { include_tag_nodes = true })
    eq(cached:broken_links(), graph:broken_links())
    eq(cached:orphan_files { include_attachments = true }, graph:orphan_files { include_attachments = true })
    eq(2, #graph:broken_links())
    eq(12, #graph:to_table().nodes)
  ]=]
end

T["filesystem fallback matches rg including hidden and gitignored files"] = function()
  child.lua [=[
    write(".gitignore", "ignored.md")
    write("ignored.md", "[[Target]]")
    write(".hidden.markdown", "#Hidden")
    write("Target.md", "#Target")
    write("image.png", "image")
    write(".git/ignored.md", "[[No]]")
    local expected = scan():to_table { include_tag_nodes = true }
    local executable = vim.fn.executable
    vim.fn.executable = function(name) return name == "rg" and 0 or executable(name) end
    local ok, actual = pcall(function() return scan():to_table { include_tag_nodes = true } end)
    vim.fn.executable = executable
    assert(ok, actual)
    eq(expected, actual)
  ]=]
end

T["rg loading keeps disk semantics for modified buffers and CRLF files"] = function()
  child.lua [=[
    local path = write("A.md", { "---\r", "tags: [Disk]\r", "---\r", "[[B]] #visible\r" })
    write("B.md", "Target")
    local buf = vim.api.nvim_create_buf(true, false)
    vim.api.nvim_buf_set_name(buf, path)
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "[[Unsaved]] #buffer" })
    local graph = scan()
    eq({}, graph:broken_links())
    eq({ "disk", "visible" }, graph:to_table().nodes[1].tags)
    eq({ { source = "note:A.md", target = "note:B.md" } }, graph:to_table().links)
    vim.api.nvim_buf_delete(buf, { force = true })
  ]=]
end

T["empty inventories return a valid empty graph"] = function()
  child.lua [=[eq({ nodes = {}, links = {} }, scan():to_table())]=]
end

T["scan errors do not produce a partial graph"] = function()
  child.lua [=[
    write("A.md", "Note")
    local parser = require "obsidian.parse.note"
    local original = parser.from_file
    parser.from_file = function() error("test parse failure") end
    local graph, err, done
    Graph.from_vault_async(function(value, message) graph, err, done = value, message, true end)
    assert(vim.wait(3000, function() return done end, 10))
    parser.from_file = original
    eq(nil, graph)
    assert(err:find("test parse failure", 1, true), err)
  ]=]
end

T["rg failures and invalid roots are explicit errors"] = function()
  child.lua [=[
    local original, executable = vim.system, vim.fn.executable
    vim.fn.executable = function(name) return name == "rg" and 1 or executable(name) end
    vim.system = function(_, _, callback)
      vim.schedule(function() callback { code = 2, stderr = "permission denied" } end)
      return { kill = function() end }
    end
    local graph, err, done
    Graph.from_vault_async(function(value, message) graph, err, done = value, message, true end)
    assert(vim.wait(3000, function() return done end, 10))
    vim.system, vim.fn.executable = original, executable
    eq(nil, graph)
    assert(err:find("permission denied", 1, true), err)
    done = false
    Graph.from_vault_async(function(value, message) graph, err, done = value, message, true end, { dir = Obsidian.dir / "absent" })
    assert(vim.wait(3000, function() return done end, 10))
    eq(nil, graph)
    assert(err:find("not a vault directory", 1, true), err)
  ]=]
end

T["cancellation suppresses callbacks"] = function()
  child.lua [=[
    write("A.md", "[[B]]")
    local called = false
    local cancel = Graph.from_vault_async(function() called = true end)
    cancel()
    vim.wait(100, function() return called end, 10)
    eq(false, called)
  ]=]
end

T["resolves in-vault file URIs and absolute paths without filesystem lookups"] = function()
  child.lua [=[
    local image = write("assets/my image.png", "image")
    local cache = require "obsidian.cache"
    cache.notes.refresh(image)
    put("folder/A.md", { links_out = {
      { kind = "markdown", target = vim.uri_from_fname(image) .. "#page=2" },
      { kind = "markdown", target = image },
      { kind = "markdown", target = "file:///outside/image.png" },
      { kind = "markdown", target = "%68ttps://example.com" },
    } })
    local graph = Graph.from_cache()
    local original = vim.uv.fs_stat
    vim.uv.fs_stat = function() error("unexpected filesystem lookup") end
    local ok, result = pcall(function() return graph:to_table() end)
    vim.uv.fs_stat = original
    assert(ok, result)
    eq({ { source = "note:folder/A.md", target = "attachment:assets/my image.png" } }, result.links)
    eq({}, graph:broken_links())
  ]=]
end

T["rg inventory preserves unusual filenames and yields across parse batches"] = function()
  child.lua [=[
    write("note with\nnewline.md", "#tag")
    for i = 1, 45 do write("note " .. i .. ".md", "[[note with%0Anewline.md]]") end
    local graph = scan()
    eq(46, #graph:to_table().nodes)
    eq(45, #graph:to_table().links)
    eq({}, graph:broken_links())
  ]=]
end

T["snapshot attachment settings do not follow later configuration changes"] = function()
  child.lua [=[
    local cache = require "obsidian.cache"
    for _, rel in ipairs { "first/image.png", "second/image.png" } do
      cache.notes.refresh(write(rel, "image"))
    end
    put("Source.md", { links_out = { { kind = "wiki", target = "image.png" } } })
    Obsidian.opts.attachments.folder = "first"
    local graph = Graph.from_cache()
    Obsidian.opts.attachments.folder = "second"
    eq("attachment:first/image.png", graph:to_table().links[1].target)
    eq("attachment:second/image.png", Graph.from_cache():to_table().links[1].target)
  ]=]
end

return T
