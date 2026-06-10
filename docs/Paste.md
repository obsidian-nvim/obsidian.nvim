Smart pasting like the Obsidian app: converts clipboard HTML to markdown, turns bare URLs into markdown links or page content, and handles file paths drag-and-dropped from terminals.

## HTML to markdown backends

HTML conversion is done by one of two external tools:

- [defuddle](https://github.com/kepano/defuddle) CLI (`npm install -g defuddle`), the library used by the Obsidian web clipper. Also extracts page metadata (title, author, description, ...) used for frontmatter.
- [pandoc](https://pandoc.org/) (`pandoc -f html -t gfm`).

By default the backend is auto-detected, preferring `defuddle` over `pandoc`. To pin one:

```lua
html = {
  backend = "pandoc", -- or "defuddle"
},
```

When the `defuddle` CLI is available, URL fetching (e.g. `link_url`, `paste_url`) also uses it locally instead of the `defuddle.md` web service.

## `:Obsidian paste`

Smart-pastes the system clipboard at the cursor:

- clipboard contains HTML (e.g. copied from a browser): converted to markdown paragraphs, no frontmatter
- clipboard is a bare URL: prompts for how to paste it (markdown link with fetched title, page content as markdown, or raw URL)
- otherwise: pasted as plain text

An optional argument forces the kind: `:Obsidian paste html`, `:Obsidian paste url`, `:Obsidian paste text`.

Bind it to a key:

```lua
vim.keymap.set("n", "<leader>p", "<cmd>Obsidian paste<cr>", { desc = "Obsidian Smart Paste" })
```

## Scripting

`actions.paste` is the interactive version powering the sub command, `api.paste` is non-interactive and fully parameterized:

```lua
-- always paste a bare URL as a markdown link, without prompting
require("obsidian.api").paste { url_as = "link" }

-- force converting clipboard HTML with pandoc
require("obsidian.api").paste { kind = "html", backend = "pandoc" }

-- paste a known URL programmatically
require("obsidian.api").paste_url("https://example.com", "content")
```

## Drag and drop

For terminals that stream drag-and-dropped files and URLs into the buffer (as bracketed paste), obsidian.nvim intercepts the paste in obsidian buffers:

- a dropped URL prompts for how to paste it (link / content / raw)
- a dropped file path is added as an attachment and a link to it is inserted

Everything else (multi-line or ordinary text pastes) is left untouched. Disable with:

```lua
paste = {
  drag_and_drop = false,
},
```

Image pasting is separate, see [[Images]] and `:Obsidian paste_img`.
