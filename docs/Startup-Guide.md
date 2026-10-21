---
title: "Getting Started"
tags:
  - getting-started
  - configuration
---

## What is obsidian.nvim?

obsidian.nvim brings vault-aware note workflows into Neovim. It works with your Markdown files and supports links, backlinks, tags, attachments, templates, daily notes, and an in-process language server (LSP). You can use it with the Obsidian app or on its own.

- **Coming from Obsidian:** Keep your existing vault and edit it in Neovim. obsidian.nvim understands Obsidian-style links, tags, frontmatter, and other Markdown conventions.
- **Coming from Neovim:** Treat a vault as a project directory. obsidian.nvim adds note-aware completion, navigation, references, code actions, and other workflows without requiring a separate language server.

## Set up your first vault

1. Install obsidian.nvim with your plugin manager. See the [installation instructions](https://github.com/obsidian-nvim/obsidian.nvim#installation).
2. Configure the path to an existing vault, or a directory where you want to keep Markdown notes:

   ```lua
   require("obsidian").setup {
     workspaces = {
       {
         name = "personal",
         path = "~/vaults/personal",
       },
     },
   }
   ```

3. Open a Markdown file inside that directory. The plugin starts its LSP for notes in the workspace; you do not need to install or configure another Markdown language server for obsidian.nvim features.
4. Try `:Obsidian` to browse available commands. Start with `:Obsidian new`, `:Obsidian quick_switch`, `:Obsidian search`, or `:Obsidian today`.

Neovim 0.11 or later is required. Install [ripgrep](https://github.com/BurntSushi/ripgrep) for search and completion features. For workspace options and setups with multiple vaults, see [[Workspace]].

## If you use the Obsidian app

Use the same vault path in both Obsidian and Neovim. The app's [Importer](https://help.obsidian.md/import) can bring notes from other tools into your vault, and the [Web Clipper](https://obsidian.md/clipper) can save pages from your browser. Both work well alongside obsidian.nvim.

The Obsidian app remains the better choice for Bases and other graphical extensions. Graph view and Canvas are especially valuable; we are working on a browser interface managed by obsidian.nvim to bring those workflows to this setup. We are also working on a Web Clipper integration that can send clipped pages to your vault without requiring the Obsidian app.

## If you are coming from Neovim

Neovim 0.11's built-in LSP mappings work with obsidian.nvim's in-process server. In Markdown buffers attached to `obsidian-ls`, you can use:

- `grn` to rename a note and update its references.
- `grr` to find references. When the results open in the quickfix list, use `[q` and `]q` to move between them.
- `gO` to browse document symbols, such as note headings.
- `gra` to open note-specific code actions, including actions for links, tags, attachments, and note operations.

Neovim's default mouse popup can also offer **Go to definition** when `obsidian-ls` is attached. These workflows use Neovim's built-in mappings, so you do not need to add plugin mappings for them.

For more:

- [[LSP]] covers navigation, rename, and code actions.
- [[Completion]] explains completion, including manual setup for Neovim's native completion.
- [[Folding]] shows how to use `vim.lsp.foldexpr()` with the plugin's heading and frontmatter folding ranges.
- [[Attachment]] explains how to customize `vim.ui.open` for attachment handling.
- [[Keymaps]] lists the plugin's own actions and suggested mappings.

## See also

[[Workspace]] · [[Commands]] · [[Keymaps]] · [[LSP]]
