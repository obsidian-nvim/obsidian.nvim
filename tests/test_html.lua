local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local html = require "obsidian.html"
local webpage = require "obsidian.webpage"

local T = new_set()

T["frontmatter"] = new_set()

T["frontmatter"]["keeps known keys in stable order and skips empty values"] = function()
  local header = webpage.frontmatter {
    title = "A Page",
    source = "https://example.com/a",
    author = "",
    description = "Desc",
    domain = "example.com", -- not whitelisted
    published = vim.NIL,
    created = "2026-06-10",
  }

  eq(
    table.concat({
      "---",
      "title: A Page",
      "source: https://example.com/a",
      "created: 2026-06-10",
      "description: Desc",
      "---",
    }, "\n"),
    header
  )
end

T["frontmatter"]["always includes a created date"] = function()
  local header = webpage.frontmatter { title = "T" }
  eq(true, header:find "created: %d%d%d%d%-%d%d%-%d%d" ~= nil)
end

T["resolve_backend"] = new_set()

T["resolve_backend"]["rejects unknown backends"] = function()
  local backend, err = html.resolve_backend "turndown"
  eq(nil, backend)
  eq(true, err:find "unknown html backend" ~= nil)
end

T["resolve_backend"]["accepts explicit backends"] = function()
  eq("pandoc", html.resolve_backend "pandoc")
  eq("defuddle", html.resolve_backend "defuddle")
end

local function convert_sync(input, opts)
  local markdown, err
  local done = false
  html.to_markdown_async(input, opts, function(md, e)
    markdown, err = md, e
    done = true
  end)
  vim.wait(10000, function()
    return done
  end, 10)
  return markdown, err
end

-- Backend tests only run when the executable is present.

if vim.fn.executable "pandoc" == 1 then
  T["to_markdown_async pandoc"] = new_set()

  T["to_markdown_async pandoc"]["fragment mode returns bare markdown"] = function()
    local markdown =
      convert_sync("<h1>Hello</h1><p>World <strong>bold</strong></p>", { backend = "pandoc", mode = "fragment" })
    eq("# Hello\n\nWorld **bold**", markdown)
  end

  T["to_markdown_async pandoc"]["page mode adds frontmatter with title and source"] = function()
    local markdown = convert_sync(
      "<html><head><title>My Page</title></head><body><p>Body</p></body></html>",
      { backend = "pandoc", mode = "page", url = "https://example.com" }
    )
    assert(markdown, "pandoc page conversion failed")
    eq(true, vim.startswith(markdown, "---\ntitle: My Page\nsource: https://example.com\n"))
    eq(true, vim.endswith(markdown, "---\n\nBody"))
  end
end

if vim.fn.executable "defuddle" == 1 then
  T["to_markdown_async defuddle"] = new_set()

  T["to_markdown_async defuddle"]["fragment mode returns bare markdown"] = function()
    local markdown = convert_sync(
      "<html><body><article><p>World <strong>bold</strong></p></article></body></html>",
      { backend = "defuddle", mode = "fragment" }
    )
    eq("World **bold**", markdown)
  end

  T["to_markdown_async defuddle"]["page mode adds frontmatter with title"] = function()
    local markdown = convert_sync(
      "<html><head><title>My Page</title></head><body><article><p>Body</p></article></body></html>",
      { backend = "defuddle", mode = "page" }
    )
    assert(markdown, "defuddle page conversion failed")
    eq(true, vim.startswith(markdown, "---\ntitle: My Page\n"))
  end
end

return T
