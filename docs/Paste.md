Smart pasting like the Obsidian app: converts clipboard HTML to markdown, saves clipboard images as attachments, turns bare URLs into markdown links or page content, and handles file paths drag-and-dropped from terminals.

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

- clipboard contains image data: saves it as an attachment and inserts the image link
- clipboard contains HTML (e.g. copied from a browser): converted to markdown paragraphs, no frontmatter
- clipboard is a bare URL: prompts for how to paste it (markdown link with fetched title, page content as markdown, or raw URL)
- otherwise: pasted as plain text

An optional argument forces the kind: `:Obsidian paste image`, `:Obsidian paste html`, `:Obsidian paste url`, `:Obsidian paste text`.

The insertion point is recorded when the paste is initiated, so you can keep moving the cursor and editing while titles or page content are fetched -- the result still lands where you pasted.

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

-- force saving clipboard image data as an attachment
require("obsidian.api").paste { kind = "image" }

-- paste a known URL programmatically
require("obsidian.api").paste_url("https://example.com", "content")
```

## Automatic paste (drag and drop, `<C-S-V>`)

When an obsidian buffer attaches, `vim.paste` is wrapped so content streamed into the buffer by the terminal -- drag-and-dropped files/URLs and bracketed paste (`<C-S-V>`) -- is handled smartly:

- clipboard HTML (including multi-line selections) is converted to markdown
- a URL prompts for how to paste it (markdown link / page content / raw)
- a URL pointing at an attachment filetype (image, pdf, ...) is downloaded into the vault and embedded
- a local file path (shell escaping and `file://` URIs are handled) prompts for how to handle it:
  - `Attach`: copy into the vault, insert a link
  - `Embed`: copy into the vault, insert an embed (`![[...]]`)
  - `Link`: insert a `file://` link to the file in place, without copying

Everything else (ordinary plain text, including multi-line plain text) is left untouched.

Guarded by `vim.g.obsidian_auto_paste`, set it to `false` (e.g. in your config, before obsidian.nvim initializes) to disable:

```lua
vim.g.obsidian_auto_paste = false
```

`:Obsidian paste_img` is kept for compatibility; prefer `:Obsidian paste image` for new mappings.
