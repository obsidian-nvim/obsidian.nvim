<h1 align="center">obsidian.nvim</h1>

<div align="center">
<a href="https://github.com/obsidian-nvim/obsidian.nvim/releases/latest">
  <img alt="Latest release" src="https://img.shields.io/github/v/release/obsidian-nvim/obsidian.nvim?style=for-the-badge&logo=starship&logoColor=D9E0EE&labelColor=302D41&&color=d9b3ff&include_prerelease&sort=semver" />
</a>
<a href="https://github.com/obsidian-nvim/obsidian.nvim/pulse">
  <img alt="Last commit" src="https://img.shields.io/github/last-commit/obsidian-nvim/obsidian.nvim?style=for-the-badge&logo=github&logoColor=D9E0EE&labelColor=302D41&color=9fdf9f"/></a>
<a href="https://github.com/neovim/neovim/releases/latest">
  <img alt="Latest Neovim" src="https://img.shields.io/github/v/release/neovim/neovim?style=for-the-badge&logo=neovim&logoColor=D9E0EE&label=Neovim&labelColor=302D41&color=99d6ff&sort=semver" />
</a>
<a href="http://www.lua.org/">
  <img alt="Made with Lua" src="https://img.shields.io/badge/Built%20with%20Lua-grey?style=for-the-badge&logo=lua&logoColor=D9E0EE&label=Lua&labelColor=302D41&color=b3b3ff">
</a>
<a href="https://dotfyle.com/plugins/obsidian-nvim/obsidian.nvim">
 <img src="https://dotfyle.com/plugins/obsidian-nvim/obsidian.nvim/shield?style=for-the-badge" />
</a>
<a href="https://github.com/obsidian-nvim/obsidian.nvim?tab=readme-ov-file#-contributing">
 <img src="https://img.shields.io/github/all-contributors/obsidian-nvim/obsidian.nvim?style=for-the-badge" />
</a>
<a href="https://github.com/orgs/obsidian-nvim/discussions">
 <img alt="GitHub Discussions" src="https://img.shields.io/github/discussions/obsidian-nvim/obsidian.nvim?style=for-the-badge">
</a>
</div>
<hr>

A **community fork** of the Neovim plugin for writing and navigating [Obsidian](https://obsidian.md) vaults, written in Lua, created by [epwalsh](https://github.com/epwalsh).

Built for people who love the concept of Obsidian -- a simple, markdown-based notes app -- but love Neovim too much to stand typing characters into anything else.

If you're new to Obsidian we highly recommend watching [this excellent YouTube video](https://youtu.be/5ht8NYkU9wQ) for a great overview.

_Keep in mind this plugin is not meant to replace Obsidian, but to complement it._ The Obsidian app is very powerful in its own way; it comes with a mobile app and has a lot of functionality that's not feasible to implement in Neovim, such as the graph explorer view. That said, this plugin stands on its own as well. You don't necessarily need to use it alongside the Obsidian app.

## 🍴 About the fork

The original project has not been actively maintained for quite a while and with the ever-changing Neovim ecosystem, new widely used tools such as [blink.cmp](https://github.com/Saghen/blink.cmp) or [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md) were not supported.

With bugs, issues and pull requests piling up, people from the community decided to fork and maintain the project. Discussions are happening in [GitHub discussions](https://github.com/obsidian-nvim/obsidian.nvim/discussions/6).

The fork aims to stay close to the original, but fix bugs, include and merge useful improvements, and ensure long term robustness.

## ⭐ Features

▶️ **Completion:** Ultra-fast, asynchronous autocompletion for note references and tags via [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) or [blink.cmp](https://github.com/Saghen/blink.cmp) (triggered by typing `[[` for wiki links, `[` for markdown links, or `#` for tags), powered by [`ripgrep`](https://github.com/BurntSushi/ripgrep).

[![See this screenshot](https://github.com/epwalsh/obsidian.nvim/assets/8812459/90d5f218-06cd-4ebb-b00b-b59c2f5c3cc1)](https://github.com/epwalsh/obsidian.nvim/assets/8812459/90d5f218-06cd-4ebb-b00b-b59c2f5c3cc1)

🏃 **Navigation:** Navigate throughout your vault by typing `gf` on any link to another note.

📷 **Images:** Paste images into notes.

📈 **Status:** See note status in statusline like obsidian app.

💅 **Syntax:** Additional markdown syntax highlighting, concealing, and extmarks for references, tags, and check-boxes.

[![See this screenshot](https://github.com/epwalsh/obsidian.nvim/assets/8812459/e74f5267-21b5-49bc-a3bb-3b9db5fa6687)](https://github.com/epwalsh/obsidian.nvim/assets/8812459/e74f5267-21b5-49bc-a3bb-3b9db5fa6687)

### Keymaps

These default keymaps will only be set if you are in a valid workspace and a markdown buffer:

- `smart_action` is the most important one you will use, it is bind to `<CR>` by default, it will
  - If cursor is on a link, follow the link
  - If cursor is on a tag, show all notes with that tag in a picker
  - If cursor is on a checkbox, toggle the checkbox
  - If cursor is on a heading, cycle the fold of that heading
- `gf`: Follow link under the cursor, falls back to normal vim `gf` if not on a link
- `<leader>ch>`: Toggle check-boxes

### Commands

- `:Obsidian backlinks` for getting a picker list of references to the current buffer.

- `:Obsidian dailies [OFFSET ...]` to open a picker list of daily notes. For example, `:Obsidian dailies -2 1` to list daily notes from 2 days ago until tomorrow.

- `:Obsidian extract_note [TITLE]` to extract the visually selected text into a new note and link to it.

- `:Obsidian follow_link [vsplit|hsplit]` to follow a note reference under the cursor, optionally opening it in a vertical or horizontal split.

- `:Obsidian link [QUERY]` to link an inline visual selection of text to a note.
  One optional argument: a query that will be used to resolve the note by ID, path, or alias. If not given, the selected text will be used as the query.

- `:Obsidian link_new [TITLE]` to create a new note and link it to an inline visual selection of text.
  One optional argument: the title of the new note. If not given, the selected text will be used as the title.

- `:Obsidian links` to collect all links within the current buffer into a picker window.

- `:Obsidian new [TITLE]` to create a new note.
  One optional argument: the title of the new note.

- `:Obsidian new_from_template [TITLE] [TEMPLATE]` to create a new note with `TITLE` from a template with the name `TEMPLATE`.
  Both arguments are optional. If not given, the template will be selected from a list using your preferred picker.

- `:Obsidian open [QUERY]` to open a note in the Obsidian app.
  One optional argument: a query used to resolve the note to open by ID, path, or alias. If not given, the current buffer is used.

- `:Obsidian paste_img [IMGNAME]` to paste an image from the clipboard into the note at the cursor position by saving it to the vault and adding a markdown image link. You can configure the default folder to save images to with the `attachments.img_folder` option.

- `:Obsidian quick_switch` to quickly switch to another note in your vault, searching by its name with a picker.

- `:Obsidian rename [NEWNAME] [--dry-run]` to rename the note of the current buffer or reference under the cursor, updating all backlinks across the vault. It is highly recommended to commit the current state of your vault (if you're using version control) before running it, or doing a dry-run first by `:Obsidian rename new-id --dry-run`.

- `:Obsidian search [QUERY]` to search for (or create) notes in your vault using `ripgrep` with your preferred picker.

- `:Obsidian tags [TAG ...]` for getting a picker list of all occurrences of the given tags.

- `:Obsidian template [NAME]` to insert a template from the templates folder, selecting from a list using your preferred picker. See [using templates](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Using-templates).

- `:Obsidian today [OFFSET]` to open/create a new daily note. This command also takes an optional offset in days, e.g. use `:Obsidian today -1` to go to yesterday's note. Unlike `:Obsidian yesterday` and `:Obsidian tomorrow` this command does not differentiate between weekdays and weekends.

- `:Obsidian tomorrow` to open/create the daily note for the next working day.

- `:Obsidian toc` to load the table of contents of the current note into a picker list.

- `:Obsidian toggle_checkbox` to cycle through checkbox options.

- `:Obsidian workspace [NAME]` to switch to another workspace.

- `:Obsidian yesterday` to open/create the daily note for the previous working day.

### Demo

[![2024-01-31 14 22 52](https://github.com/epwalsh/obsidian.nvim/assets/8812459/2986e1d2-13e8-40e2-9c9e-75691a3b662e)](https://github.com/epwalsh/obsidian.nvim/assets/8812459/2986e1d2-13e8-40e2-9c9e-75691a3b662e)

## 📝 Requirements

### System requirements

- Neovim >= 0.10.0
- For completion and search features:

  - Backend: [ripgrep](https://github.com/BurntSushi/ripgrep), see [ripgrep#installation](https://github.com/BurntSushi/ripgrep)
  - Frontend: a picker, see [Plugin dependencies](#plugin-dependencies)

- Additional system dependencies:

  - **Windows WSL** users need [`wsl-open`](https://gitlab.com/4U6U57/wsl-open) for `:Obsidian open`.
  - **MacOS** users need [`pngpaste`](https://github.com/jcsalterego/pngpaste) (`brew install pngpaste`) for `:Obsidian paste_img`.
  - **Linux** users need xclip (X11) or wl-clipboard (Wayland) for `:Obsidian paste_img`.

### Plugin dependencies

The only **required** plugin dependency is [plenary.nvim](https://github.com/nvim-lua/plenary.nvim), but there are a number of optional dependencies that enhance the obsidian.nvim experience.

**Completion:**

- **[recommended]** [hrsh7th/nvim-cmp](https://github.com/hrsh7th/nvim-cmp)
- [blink.cmp](https://github.com/Saghen/blink.cmp) (new)

**Pickers:**

- **[recommended]** [nvim-telescope/telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [ibhagwan/fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [Mini.Pick](https://github.com/echasnovski/mini.pick) from the mini.nvim library
- [Snacks.Picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md) from the snacks.nvim library

**Syntax highlighting:**

See [syntax highlighting](#syntax-highlighting) for more details.

- For base syntax highlighting:
  - **[recommended]** [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
  - [preservim/vim-markdown](https://github.com/preservim/vim-markdown)
- For additional syntax features:
  - [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
  - [markview.nvim](https://github.com/OXY2DEV/markview.nvim)

If you choose to use any of these you should include them in the "dependencies" or "requires" field of the obsidian.nvim plugin spec for your package manager.

## 📥 Installation

To configure obsidian.nvim you just need to call `require("obsidian").setup({ ... })` with the desired options.
Here are some examples using different plugin managers. The full set of [plugin dependencies](#plugin-dependencies) and [configuration options](#configuration-options) are listed below.

> [!WARNING]
> If you install from the latest release (recommended for stability) instead of `main`, be aware that the README on `main` may reference features that haven't been released yet. For that reason I recommend viewing the README on the tag for the [latest release](https://github.com/obsidian-nvim/obsidian.nvim/releases) instead of `main`.

> [!TIP]
> To see your installation status, run `:checkhealth obsidian`
>
> To try out or debug this plugin, use `minimal.lua` in the repo to run a clean instance of obsidian.nvim

### Using [`lazy.nvim`](https://github.com/folke/lazy.nvim)

<details><summary>Click for install snippet</summary>

```lua
return {
  "obsidian-nvim/obsidian.nvim",
  version = "*", -- recommended, use latest release instead of latest commit
  lazy = true,
  ft = "markdown",
  -- Replace the above line with this if you only want to load obsidian.nvim for markdown files in your vault:
  -- event = {
  --   -- If you want to use the home shortcut '~' here you need to call 'vim.fn.expand'.
  --   -- E.g. "BufReadPre " .. vim.fn.expand "~" .. "/my-vault/*.md"
  --   -- refer to `:h file-pattern` for more examples
  --   "BufReadPre path/to/my-vault/*.md",
  --   "BufNewFile path/to/my-vault/*.md",
  -- },
  dependencies = {
    -- Required.
    "nvim-lua/plenary.nvim",

    -- see above for full list of optional dependencies ☝️
  },
  ---@module 'obsidian'
  ---@type obsidian.config.ClientOpts
  opts = {
    workspaces = {
      {
        name = "personal",
        path = "~/vaults/personal",
      },
      {
        name = "work",
        path = "~/vaults/work",
      },
    },

    -- see below for full list of options 👇
  },
}
```

</details>

### Using [`rocks.nvim`](https://github.com/nvim-neorocks/rocks.nvim)

<details><summary>Click for install snippet</summary>

```vim
:Rocks install obsidian
```

</details>

### Using [`packer.nvim`](https://github.com/wbthomason/packer.nvim)

It is not recommended because packer.nvim is currently unmaintained

<details><summary>Click for install snippet</summary>

```lua
use {
  "obsidian-nvim/obsidian.nvim",
  tag = "*", -- recommended, use latest release instead of latest commit
  requires = {
    -- Required.
    "nvim-lua/plenary.nvim",

    -- see above for full list of optional dependencies ☝️
  },
  config = function()
    require("obsidian").setup {
      workspaces = {
        {
          name = "personal",
          path = "~/vaults/personal",
        },
        {
          name = "work",
          path = "~/vaults/work",
        },
      },

      -- see below for full list of options 👇
    }
  end,
}
```

</details>

## ⚙️ Configuration

This is a complete list of all the options that can be passed to `require("obsidian").setup()`. The settings below are _not necessarily the defaults, but represent reasonable default settings_. Please read each option carefully and customize it to your needs.

<details><summary><bold>Click to see configuration options</bold></summary>

```lua
require("obsidian").setup {
  -- A list of workspace names, paths, and configuration overrides.
  -- If you use the Obsidian app, the 'path' of a workspace should generally be
  -- your vault root (where the `.obsidian` folder is located).
  -- When obsidian.nvim is loaded by your plugin manager, it will automatically set
  -- the workspace to the first workspace in the list whose `path` is a parent of the
  -- current markdown file being edited.
  workspaces = {
    {
      name = "personal",
      path = "~/vaults/personal",
    },
    {
      name = "work",
      path = "~/vaults/work",
      -- Optional, override certain settings.
      overrides = {
        notes_subdir = "notes",
      },
    },
  },

  -- Alternatively - and for backwards compatibility - you can set 'dir' to a single path instead of
  -- 'workspaces'. For example:
  -- dir = "~/vaults/work",

  -- Optional, if you keep notes in a specific subdirectory of your vault.
  notes_subdir = "notes",

  -- Optional, set the log level for obsidian.nvim. This is an integer corresponding to one of the log
  -- levels defined by "vim.log.levels.\*".
  log_level = vim.log.levels.INFO,

  daily_notes = {
    -- Optional, if you keep daily notes in a separate directory.
    folder = "notes/dailies",
    -- Optional, if you want to change the date format for the ID of daily notes.
    date_format = "%Y-%m-%d",
    -- Optional, if you want to change the date format of the default alias of daily notes.
    alias_format = "%B %-d, %Y",
    -- Optional, default tags to add to each new daily note created.
    default_tags = { "daily-notes" },
    -- Optional, if you want to automatically insert a template from your template directory like 'daily.md'
    template = nil,
    -- Optional, if you want `Obsidian yesterday` to return the last work day or `Obsidian tomorrow` to return the next work day.
    workdays_only = true,
  },

  -- Optional, completion of wiki links, local markdown links, and tags using nvim-cmp.
  completion = {
    -- Enables completion using nvim_cmp
    nvim_cmp = true,
    -- Enables completion using blink.cmp
    blink = false,
    -- Trigger completion at 2 chars.
    min_chars = 2,
  },

  -- Optional, configure key mappings. These are the defaults. If you don't want to set any keymappings this
  -- way then set 'mappings = {}'.
  mappings = {
    -- Overrides the 'gf' mapping to work on markdown/wiki links within your vault.
    ["gf"] = {
      action = function()
        return require("obsidian").util.gf_passthrough()
      end,
      opts = { noremap = false, expr = true, buffer = true },
    },
    -- Toggle check-boxes.
    ["<leader>ch"] = {
      action = function()
        return require("obsidian").util.toggle_checkbox()
      end,
      opts = { buffer = true },
    },
    -- Smart action depending on context: follow link, show notes with tag, toggle checkbox, or toggle heading fold
    ["<cr>"] = {
      action = function()
        return require("obsidian").util.smart_action()
      end,
      opts = { buffer = true, expr = true },
    },
  },

  -- Where to put new notes. Valid options are
  -- _ "current_dir" - put new notes in same directory as the current buffer.
  -- _ "notes_subdir" - put new notes in the default notes subdirectory.
  new_notes_location = "notes_subdir",

  -- Optional, customize how note IDs are generated given an optional title.
  ---@param title string|?
  ---@return string
  note_id_func = function(title)
    -- Create note IDs in a Zettelkasten format with a timestamp and a suffix.
    -- In this case a note with the title 'My new note' will be given an ID that looks
    -- like '1657296016-my-new-note', and therefore the file name '1657296016-my-new-note.md'.
    -- You may have as many periods in the note ID as you'd like—the ".md" will be added automatically
    local suffix = ""
    if title ~= nil then
      -- If title is given, transform it into valid file name.
      suffix = title:gsub(" ", "-"):gsub("[^A-Za-z0-9-]", ""):lower()
    else
      -- If title is nil, just add 4 random uppercase letters to the suffix.
      for _ = 1, 4 do
        suffix = suffix .. string.char(math.random(65, 90))
      end
    end
    return tostring(os.time()) .. "-" .. suffix
  end,

  -- Optional, customize how note file names are generated given the ID, target directory, and title.
  ---@param spec { id: string, dir: obsidian.Path, title: string|? }
  ---@return string|obsidian.Path The full path to the new note.
  note_path_func = function(spec)
    -- This is equivalent to the default behavior.
    local path = spec.dir / tostring(spec.id)
    return path:with_suffix ".md"
  end,

  -- Optional, customize how wiki links are formatted. You can set this to one of:
  -- _ "use_alias_only", e.g. '[[Foo Bar]]'
  -- _ "prepend*note_id", e.g. '[[foo-bar|Foo Bar]]'
  -- * "prepend*note_path", e.g. '[[foo-bar.md|Foo Bar]]'
  -- * "use_path_only", e.g. '[[foo-bar.md]]'
  -- Or you can set it to a function that takes a table of options and returns a string, like this:
  wiki_link_func = function(opts)
    return require("obsidian.util").wiki_link_id_prefix(opts)
  end,

  -- Optional, customize how markdown links are formatted.
  markdown_link_func = function(opts)
    return require("obsidian.util").markdown_link(opts)
  end,

  -- Either 'wiki' or 'markdown'.
  preferred_link_style = "wiki",

  -- Optional, boolean or a function that takes a filename and returns a boolean.
  -- `true` indicates that you don't want obsidian.nvim to manage frontmatter.
  disable_frontmatter = false,

  -- Optional, alternatively you can customize the frontmatter data.
  ---@return table
  note_frontmatter_func = function(note)
    -- Add the title of the note as an alias.
    if note.title then
      note:add_alias(note.title)
    end

    local out = { id = note.id, aliases = note.aliases, tags = note.tags }

    -- `note.metadata` contains any manually added fields in the frontmatter.
    -- So here we just make sure those fields are kept in the frontmatter.
    if note.metadata ~= nil and not vim.tbl_isempty(note.metadata) then
      for k, v in pairs(note.metadata) do
        out[k] = v
      end
    end

    return out
  end,

  -- Optional, for templates (see https://github.com/obsidian-nvim/obsidian.nvim/wiki/Using-templates)
  templates = {
    folder = "templates",
    date_format = "%Y-%m-%d",
    time_format = "%H:%M",
    -- A map for custom variables, the key should be the variable and the value a function
    substitutions = {},
  },

  -- Sets how you follow URLs
  ---@param url string
  follow_url_func = function(url)
    vim.ui.open(url)
    -- vim.ui.open(url, { cmd = { "firefox" } })
  end,

  -- Sets how you follow images
  ---@param img string
  follow_img_func = function(img)
    vim.ui.open(img)
    -- vim.ui.open(img, { cmd = { "loupe" } })
  end,

  -- Optional, set to true if you use the Obsidian Advanced URI plugin.
  -- https://github.com/Vinzent03/obsidian-advanced-uri
  use_advanced_uri = false,

  -- Optional, set to true to force ':Obsidian open' to bring the app to the foreground.
  open_app_foreground = false,

  picker = {
    -- Set your preferred picker. Can be one of 'telescope.nvim', 'fzf-lua', 'mini.pick' or 'snacks.pick'.
    name = "telescope.nvim",
    -- Optional, configure key mappings for the picker. These are the defaults.
    -- Not all pickers support all mappings.
    note_mappings = {
      -- Create a new note from your query.
      new = "<C-x>",
      -- Insert a link to the selected note.
      insert_link = "<C-l>",
    },
    tag_mappings = {
      -- Add tag(s) to current note.
      tag_note = "<C-x>",
      -- Insert a tag at the current location.
      insert_tag = "<C-l>",
    },
  },

  -- Optional, by default, `:ObsidianBacklinks` parses the header under
  -- the cursor. Setting to `false` will get the backlinks for the current
  -- note instead. Doesn't affect other link behaviour.
  backlinks = {
    parse_headers = true
  }

  -- Optional, sort search results by "path", "modified", "accessed", or "created".
  -- The recommend value is "modified" and `true` for `sort_reversed`, which means, for example,
  -- that `:Obsidian quick_switch` will show the notes sorted by latest modified time
  sort_by = "modified",
  sort_reversed = true,

  -- Set the maximum number of lines to read from notes on disk when performing certain searches.
  search_max_lines = 1000,

  -- Optional, determines how certain commands open notes. The valid options are:
  -- 1. "current" (the default) - to always open in the current window
  -- 2. "vsplit" - to open in a vertical split if there's not already a vertical split
  -- 3. "hsplit" - to open in a horizontal split if there's not already a horizontal split
  open_notes_in = "current",

  -- Optional, define your own callbacks to further customize behavior.
  callbacks = {
    -- Runs at the end of `require("obsidian").setup()`.
    ---@param client obsidian.Client
    post_setup = function(client) end,

    -- Runs anytime you enter the buffer for a note.
    ---@param client obsidian.Client
    ---@param note obsidian.Note
    enter_note = function(client, note) end,

    -- Runs anytime you leave the buffer for a note.
    ---@param client obsidian.Client
    ---@param note obsidian.Note
    leave_note = function(client, note) end,

    -- Runs right before writing the buffer for a note.
    ---@param client obsidian.Client
    ---@param note obsidian.Note
    pre_write_note = function(client, note) end,

    -- Runs anytime the workspace is set/changed.
    ---@param client obsidian.Client
    ---@param workspace obsidian.Workspace
    post_set_workspace = function(client, workspace) end,
  },

  -- Optional, configure additional syntax highlighting / extmarks.
  -- This requires you have `conceallevel` set to 1 or 2. See `:help conceallevel` for more details.
  ui = {
    enable = true, -- set to false to disable all additional syntax features
    ignore_conceal_warn = false, -- set to true to disable conceallevel specific warning
    update_debounce = 200, -- update delay after a text change (in milliseconds)
    max_file_length = 5000, -- disable UI features for files with more than this many lines
    -- Define how various check-boxes are displayed
    checkboxes = {
      -- NOTE: the 'char' value has to be a single character, and the highlight groups are defined below.
      [" "] = { char = "󰄱", hl_group = "ObsidianTodo" },
      ["x"] = { char = "", hl_group = "ObsidianDone" },
      [">"] = { char = "", hl_group = "ObsidianRightArrow" },
      ["~"] = { char = "󰰱", hl_group = "ObsidianTilde" },
      ["!"] = { char = "", hl_group = "ObsidianImportant" },
      -- Replace the above with this if you don't have a patched font:
      -- [" "] = { char = "☐", hl_group = "ObsidianTodo" },
      -- ["x"] = { char = "✔", hl_group = "ObsidianDone" },

      -- You can also add more custom ones...
    },
    -- Use bullet marks for non-checkbox lists.
    bullets = { char = "•", hl_group = "ObsidianBullet" },
    external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
    -- Replace the above with this if you don't have a patched font:
    -- external_link_icon = { char = "", hl_group = "ObsidianExtLinkIcon" },
    reference_text = { hl_group = "ObsidianRefText" },
    highlight_text = { hl_group = "ObsidianHighlightText" },
    tags = { hl_group = "ObsidianTag" },
    block_ids = { hl_group = "ObsidianBlockID" },
    hl_groups = {
      -- The options are passed directly to `vim.api.nvim_set_hl()`. See `:help nvim_set_hl`.
      ObsidianTodo = { bold = true, fg = "#f78c6c" },
      ObsidianDone = { bold = true, fg = "#89ddff" },
      ObsidianRightArrow = { bold = true, fg = "#f78c6c" },
      ObsidianTilde = { bold = true, fg = "#ff5370" },
      ObsidianImportant = { bold = true, fg = "#d73128" },
      ObsidianBullet = { bold = true, fg = "#89ddff" },
      ObsidianRefText = { underline = true, fg = "#c792ea" },
      ObsidianExtLinkIcon = { fg = "#c792ea" },
      ObsidianTag = { italic = true, fg = "#89ddff" },
      ObsidianBlockID = { italic = true, fg = "#89ddff" },
      ObsidianHighlightText = { bg = "#75662e" },
    },
  },

  -- Specify how to handle attachments.
  attachments = {
    -- The default folder to place images in via `:Obsidian paste_img`.
    -- If this is a relative path it will be interpreted as relative to the vault root.
    -- You can always override this per image by passing a full path to the command instead of just a filename.
    img_folder = "assets/imgs", -- This is the default

    -- A function that determines default name or prefix when pasting images via `:Obsidian paste_img`.
    ---@return string
    img_name_func = function()
      -- Prefix image names with timestamp.
      return string.format("Pasted image %s", os.date "%Y%m%d%H%M%S")
    end,

    -- A function that determines the text to insert in the note when pasting an image.
    -- It takes two arguments, the `obsidian.Client` and an `obsidian.Path` to the image file.
    -- This is the default implementation.
    ---@param client obsidian.Client
    ---@param path obsidian.Path the absolute path to the image file
    ---@return string
    img_text_func = function(client, path)
      path = client:vault_relative_path(path) or path
      return string.format("![%s](%s)", path.name, path)
    end,
  },

  -- See https://github.com/obsidian-nvim/obsidian.nvim/wiki/Notes-on-configuration#statusline-component
  statusline = {
    enabled = true,
    format = "{{properties}} properties {{backlinks}} backlinks {{words}} words {{chars}} chars",
  },
}
```

</details>

## 📖 Documentation

See the [obsidian.nvim wiki](https://github.com/obsidian-nvim/obsidian.nvim/wiki)

## 🤝 Contributing

Please read the [CONTRIBUTING](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/CONTRIBUTING.md) guide before submitting a pull request.

<!-- ALL-CONTRIBUTORS-LIST:START - Do not remove or modify this section -->
<!-- prettier-ignore-start -->
<!-- markdownlint-disable -->
<table>
  <tbody>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/neo451"><img src="https://avatars.githubusercontent.com/u/111681693?v=4?s=100" width="100px;" alt="neo451"/><br /><sub><b>neo451</b></sub></a><br /><a href="#code-neo451" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sotte"><img src="https://avatars.githubusercontent.com/u/79138?v=4?s=100" width="100px;" alt="Stefan Otte"/><br /><sub><b>Stefan Otte</b></sub></a><br /><a href="#code-sotte" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/guspix"><img src="https://avatars.githubusercontent.com/u/33852783?v=4?s=100" width="100px;" alt="guspix"/><br /><sub><b>guspix</b></sub></a><br /><a href="#code-guspix" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ffricken"><img src="https://avatars.githubusercontent.com/u/44709001?v=4?s=100" width="100px;" alt="ffricken"/><br /><sub><b>ffricken</b></sub></a><br /><a href="#code-ffricken" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ErlanRG"><img src="https://avatars.githubusercontent.com/u/32745670?v=4?s=100" width="100px;" alt="Erlan Rangel"/><br /><sub><b>Erlan Rangel</b></sub></a><br /><a href="#code-ErlanRG" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/bosvik"><img src="https://avatars.githubusercontent.com/u/132846580?v=4?s=100" width="100px;" alt="bosvik"/><br /><sub><b>bosvik</b></sub></a><br /><a href="#code-bosvik" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://alemann.dev"><img src="https://avatars.githubusercontent.com/u/58050402?v=4?s=100" width="100px;" alt="Jost Alemann"/><br /><sub><b>Jost Alemann</b></sub></a><br /><a href="#doc-ddogfoodd" title="Documentation">📖</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/ottersome"><img src="https://avatars.githubusercontent.com/u/9465391?v=4?s=100" width="100px;" alt="Luis Garcia"/><br /><sub><b>Luis Garcia</b></sub></a><br /><a href="#code-ottersome" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/jblsp"><img src="https://avatars.githubusercontent.com/u/48526917?v=4?s=100" width="100px;" alt="Joe"/><br /><sub><b>Joe</b></sub></a><br /><a href="#code-jblsp" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/horiagug"><img src="https://avatars.githubusercontent.com/u/23277222?v=4?s=100" width="100px;" alt="Horia Gug"/><br /><sub><b>Horia Gug</b></sub></a><br /><a href="#code-horiagug" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://www.linkedin.com/in/aquilesgomez"><img src="https://avatars.githubusercontent.com/u/20983181?v=4?s=100" width="100px;" alt="Aquiles Gomez"/><br /><sub><b>Aquiles Gomez</b></sub></a><br /><a href="#code-aquilesg" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/alvarosevilla95"><img src="https://avatars.githubusercontent.com/u/1376447?v=4?s=100" width="100px;" alt="Alvaro Sevilla"/><br /><sub><b>Alvaro Sevilla</b></sub></a><br /><a href="#code-alvarosevilla95" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/sstark"><img src="https://avatars.githubusercontent.com/u/837918?v=4?s=100" width="100px;" alt="Sebastian Stark"/><br /><sub><b>Sebastian Stark</b></sub></a><br /><a href="#code-sstark" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Peeeaje"><img src="https://avatars.githubusercontent.com/u/74146834?v=4?s=100" width="100px;" alt="Jumpei Yamakawa"/><br /><sub><b>Jumpei Yamakawa</b></sub></a><br /><a href="#code-Peeeaje" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/marcocofano"><img src="https://avatars.githubusercontent.com/u/63420833?v=4?s=100" width="100px;" alt="marcocofano"/><br /><sub><b>marcocofano</b></sub></a><br /><a href="#code-marcocofano" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Jaehaks"><img src="https://avatars.githubusercontent.com/u/26200835?v=4?s=100" width="100px;" alt="Jaehaks"/><br /><sub><b>Jaehaks</b></sub></a><br /><a href="#code-Jaehaks" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://www.linkedin.com/in/magnusriga/"><img src="https://avatars.githubusercontent.com/u/38915578?v=4?s=100" width="100px;" alt="Magnus"/><br /><sub><b>Magnus</b></sub></a><br /><a href="#code-magnusriga" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/noamsto"><img src="https://avatars.githubusercontent.com/u/17932324?v=4?s=100" width="100px;" alt="Noam Stolero"/><br /><sub><b>Noam Stolero</b></sub></a><br /><a href="#code-noamsto" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/aileot"><img src="https://avatars.githubusercontent.com/u/46470475?v=4?s=100" width="100px;" alt="aileot"/><br /><sub><b>aileot</b></sub></a><br /><a href="#code-aileot" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://ricostacruz.com/"><img src="https://avatars.githubusercontent.com/u/74385?v=4?s=100" width="100px;" alt="Rico Sta. Cruz"/><br /><sub><b>Rico Sta. Cruz</b></sub></a><br /><a href="#doc-rstacruz" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/hnjae"><img src="https://avatars.githubusercontent.com/u/42675338?v=4?s=100" width="100px;" alt="KIM Hyunjae"/><br /><sub><b>KIM Hyunjae</b></sub></a><br /><a href="#code-hnjae" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/bburgess19"><img src="https://avatars.githubusercontent.com/u/55334507?v=4?s=100" width="100px;" alt="Ben Burgess"/><br /><sub><b>Ben Burgess</b></sub></a><br /><a href="#code-bburgess19" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://sebszyller.com"><img src="https://avatars.githubusercontent.com/u/11989990?v=4?s=100" width="100px;" alt="Sebastian Szyller"/><br /><sub><b>Sebastian Szyller</b></sub></a><br /><a href="#code-sebszyller" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->

## ❤️ Acknowledgement

We would like to thank [epwalsh](https://github.com/epwalsh) for creating this beautiful plugin. If you're feeling especially generous, [he still appreciates some coffee funds!](https://www.buymeacoffee.com/epwalsh).
