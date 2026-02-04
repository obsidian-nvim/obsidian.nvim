<!--markdoc_ignore_start-->
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
<a href="https://github.com/obsidian-nvim/obsidian.nvim/releases.atom">
  <img src="https://img.shields.io/badge/rss-F88900?style=for-the-badge&logo=rss&logoColor=white">
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
<!--markdoc_ignore_end-->

A **community fork** of the Neovim plugin for writing and navigating [Obsidian](https://obsidian.md) vaults, written in Lua, created by [epwalsh](https://github.com/epwalsh).

Built for people who love the concept of Obsidian -- a simple, markdown-based notes app -- but love Neovim too much to stand typing characters into anything else.

_This plugin is not meant to replace Obsidian, but to complement it._ The Obsidian app comes with a mobile app and has a lot of functionality that's not feasible to implement in Neovim, such as the graph explorer view. That said, this plugin stands on its own as well. You don't necessarily need to use it alongside the Obsidian app.

## 🍴 About the fork

The original project has not been actively maintained for quite a while and with the ever-changing Neovim ecosystem, new widely used tools such as [blink.cmp](https://github.com/Saghen/blink.cmp) or [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md) were not supported.

With bugs, issues and pull requests piling up, people from the community decided to fork and maintain the project.

- Discussions are happening in [GitHub Discussions](https://github.com/obsidian-nvim/obsidian.nvim/discussions/6)
- Sponsor the project at [Open Collective](https://opencollective.com/nvim-obsidian)
- See [Breaking changes](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Breaking-Changes) to migrate from original repo or older releases
- See the latest documentation in [obsidian.nvim wiki](https://github.com/obsidian-nvim/obsidian.nvim/wiki), or navigate the wiki in neovim with `:Obsidian help` or `:Obsidian helpgrep`, which is the most accurate and versioned documentation of your local install.

## ⭐ Features

▶️ **Completion:** Ultra-fast, asynchronous autocompletion for note references and tags via [nvim-cmp](https://github.com/hrsh7th/nvim-cmp) or [blink.cmp](https://github.com/Saghen/blink.cmp) (triggered by typing `[[` for wiki links, `[` for markdown links, or `#` for tags)

🏃 **Navigation:** Navigate throughout your vault via links, backlinks, tags and etc.

📷 **Images:** Paste images into notes.

📈 **Status:** See note status in footer like obsidian app.

### Keymaps

- `smart_action`, bind to `<CR>` will:
  - If cursor is on a link, follow the link.
  - If cursor is on a tag, show all notes with that tag in a picker.
  - If cursor is on a checkbox, toggle the checkbox, see [Checkbox.create_new](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Checkbox#create-new).
  - If cursor is on a heading, cycle the fold of that heading, see [Folding](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Folding) to set this up.
- `nav_link`, bind to `[o` and `]o` will navigate cursor to next valid link in the buffer.

For other available actions and remapping default ones, see [Keymaps](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Keymaps)

### Commands

There's one entry point user command for this plugin: `Obsidian`

- `Obsidian<CR>` (`<enter>`) to select sub commands.
- `Obsidian <Tab>` to get completion for sub commands.
- Sub commands are context sensitive, meaning some actions will only appear when:
  - you are in a note.
  - you are in visual mode.
- See [Commands](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Commands) for more info.

#### Top level commands

- `:Obsidian dailies [OFFSET ...]` - open a picker list of daily notes
  - `:Obsidian dailies -2 1` to list daily notes from 2 days ago until tomorrow
- `:Obsidian help` - find files in the help wiki
- `:Obsidian helpgrep` - grep files in the help wiki
- `:Obsidian new [TITLE]` - create a new note
- `:Obsidian open [QUERY]` - open a note in the Obsidian app
  - query is used to resolve the note to open by ID, path, or alias, else use current note
- `:Obsidian today [OFFSET]` - open/create a new daily note
  - offset is in days, e.g. use `:Obsidian today -1` to go to yesterday's note.
  - Unlike `:Obsidian yesterday` and `:Obsidian tomorrow` this command does not differentiate between weekdays and weekends
- `:Obsidian tomorrow` - open/create the daily note for the next working day
- `:Obsidian yesterday` - open/create the daily note for the previous working day
- `:Obsidian new_from_template [TITLE] [TEMPLATE]` - create a new note with `TITLE` from a template with the name `TEMPLATE`
  - both arguments are optional. If not given, the template will be selected from a list using your preferred picker
- `:Obsidian quick_switch` - switch to another note in your vault, searching by its name with a picker
- `:Obsidian search [QUERY]` - search for (or create) notes in your vault using `ripgrep` with your preferred picker
- `:Obsidian tags [TAG ...]` - get a picker list of all occurrences of the given tags
- `:Obsidian workspace [NAME]` - switch to another workspace

#### Note commands

- `:Obsidian backlinks` - get a picker list of references to the current note
  - `grr`/`vim.lsp.buf.references` to see references in quickfix list
- `:Obsidian follow_link [STRATEGY]` - follow a note reference under the cursor
  - available strategies: `vsplit, hsplit, vsplit_force, hsplit_force`
- `:Obsidian toc` - get a picker list of table of contents for current note
- `:Obsidian template [NAME]` - insert a template from the templates folder, selecting from a list using your preferred picker
  - [Template](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Template)
- `:Obsidian links` - get a picker list of all links in current note
- `:Obsidian paste_img [IMGNAME]` - paste an image from the clipboard into the note at the cursor position by saving it to the vault and adding a markdown image link
  - [Images](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Images#change-image-save-location)
- `:Obsidian rename [NEWNAME]` - rename the note of the current buffer or reference under the cursor, updating all backlinks across the vault
  - runs `:wa` before renaming, and loads every note with backlinks into your buffer-list
  - after renaming you need to do `:wa` again for changes to take effect
  - alternatively, call `vim.lsp.buf.rename` or use `grn`
- `:Obsidian toggle_checkbox` - cycle through checkbox options

#### Visual mode commands

- `:Obsidian extract_note [TITLE]` - extract the visually selected text into a new note and link to it
- `:Obsidian link [QUERY]` - link an inline visual selection of text to a note
  - query will be used to resolve the note by ID, path, or alias, else query is selected text
- `:Obsidian link_new [TITLE]` - create a new note and link it to an inline visual selection of text
  - if title is not given, selected text is used

## 📝 Requirements

### System requirements

- Neovim >= 0.10.0
- For completion and search features: [`ripgrep`](https://github.com/BurntSushi/ripgrep?tab=readme-ov-file#installation)
- Additional system dependencies:
  - **Windows WSL** users need [`wsl-open`](https://gitlab.com/4U6U57/wsl-open) for `:Obsidian open`.
  - **MacOS** users need [`pngpaste`](https://github.com/jcsalterego/pngpaste) (`brew install pngpaste`) for `:Obsidian paste_img`.
  - **Linux** users need `xclip` (X11) or `wl-clipboard` (Wayland) for `:Obsidian paste_img`.

### Plugin dependencies

There's no required dependency, but there are a number of optional dependencies that enhance the obsidian.nvim experience.

**Completion:**

- [blink.cmp](https://github.com/Saghen/blink.cmp)
- [nvim-cmp](https://github.com/hrsh7th/nvim-cmp)

**Pickers:**

- [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim)
- [fzf-lua](https://github.com/ibhagwan/fzf-lua)
- [mini.pick](https://github.com/echasnovski/mini.pick)
- [snacks.picker](https://github.com/folke/snacks.nvim/blob/main/docs/picker.md)

**Image viewing:**

- [snacks.image](https://github.com/folke/snacks.nvim/blob/main/docs/image.md)
- See [Images](https://github.com/obsidian-nvim/obsidian.nvim/wiki/Images) for configuration.

**Syntax highlighting:**

See [syntax highlighting](#syntax-highlighting) for more details.

- For base syntax highlighting:
  - [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter)
  - [vim-markdown](https://github.com/preservim/vim-markdown)
- For additional syntax features:
  - [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim)
  - [markview.nvim](https://github.com/OXY2DEV/markview.nvim)

## 📥 Installation

> [!WARNING]
> For stability you may want to use latest release, be aware that the README on `main` may reference features that haven't been released yet.
>
> So view the README on the tag for the [latest release](https://github.com/obsidian-nvim/obsidian.nvim/releases) instead of `main`.

> [!TIP]
> To see your installation status, run `:checkhealth obsidian`
>
> To try out or debug this plugin, run `nvim -u minimal.lua` to try in a clean environment

### Using [`lazy.nvim`](https://github.com/folke/lazy.nvim)

```lua
return {
  "obsidian-nvim/obsidian.nvim",
  version = "*", -- use latest release, remove to use latest commit
  ft = "markdown",
  ---@module 'obsidian'
  ---@type obsidian.config
  opts = {
    legacy_commands = false, -- this will be removed in the next major release
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
  },
}
```

### Using [`rocks.nvim`](https://github.com/nvim-neorocks/rocks.nvim)

```vim
:Rocks install obsidian.nvim
```

### Using `vim.pack` (nvim-0.12+)

```lua
vim.pack.add {
  {
    src = "https://github.com/obsidian-nvim/obsidian.nvim",
    version = vim.version.range "*", -- use latest release, remove to use latest commit
  },
}
```

## ⚙️ Configuration

To configure obsidian.nvim, pass your custom options that are different from [default options](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/lua/obsidian/config/default.lua) to `require"obsidian".setup()`.

## 🤝 Contributing

Please read the [CONTRIBUTING](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/CONTRIBUTING.md) guide before submitting a pull request.

<!--markdoc_ignore_start-->
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
      <td align="center" valign="top" width="14.28%"><a href="http://nobe4.fr"><img src="https://avatars.githubusercontent.com/u/2452791?v=4?s=100" width="100px;" alt="nobe4"/><br /><sub><b>nobe4</b></sub></a><br /><a href="#code-nobe4" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Anaritus"><img src="https://avatars.githubusercontent.com/u/61704392?v=4?s=100" width="100px;" alt="Anaritus"/><br /><sub><b>Anaritus</b></sub></a><br /><a href="#code-Anaritus" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/mdavis36"><img src="https://avatars.githubusercontent.com/u/25917313?v=4?s=100" width="100px;" alt="Michael Davis"/><br /><sub><b>Michael Davis</b></sub></a><br /><a href="#code-mdavis36" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://brianrodri.com"><img src="https://avatars.githubusercontent.com/u/5094060?v=4?s=100" width="100px;" alt="Brian Rodriguez"/><br /><sub><b>Brian Rodriguez</b></sub></a><br /><a href="#code-brianrodri" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/carschandler"><img src="https://avatars.githubusercontent.com/u/92899389?v=4?s=100" width="100px;" alt="carschandler"/><br /><sub><b>carschandler</b></sub></a><br /><a href="#doc-carschandler" title="Documentation">📖</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://escapewindow.com"><img src="https://avatars.githubusercontent.com/u/826343?v=4?s=100" width="100px;" alt="Aki Sasaki"/><br /><sub><b>Aki Sasaki</b></sub></a><br /><a href="#code-escapewindow" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://www.linkedin.com/in/rim18/"><img src="https://avatars.githubusercontent.com/u/5428479?v=4?s=100" width="100px;" alt="Reinaldo Molina"/><br /><sub><b>Reinaldo Molina</b></sub></a><br /><a href="#code-tricktux" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/srackham"><img src="https://avatars.githubusercontent.com/u/674468?v=4?s=100" width="100px;" alt="Stuart Rackham"/><br /><sub><b>Stuart Rackham</b></sub></a><br /><a href="#code-srackham" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://redoxahmii.vercel.app"><img src="https://avatars.githubusercontent.com/u/13983258?v=4?s=100" width="100px;" alt="Ahmed Mughal"/><br /><sub><b>Ahmed Mughal</b></sub></a><br /><a href="#code-redoxahmii" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/trash-panda-v91-beta"><img src="https://avatars.githubusercontent.com/u/42897550?v=4?s=100" width="100px;" alt="trash-panda-v91-beta"/><br /><sub><b>trash-panda-v91-beta</b></sub></a><br /><a href="#code-trash-panda-v91-beta" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://westhoffswelt.de"><img src="https://avatars.githubusercontent.com/u/160529?v=4?s=100" width="100px;" alt="Jakob Westhoff"/><br /><sub><b>Jakob Westhoff</b></sub></a><br /><a href="#code-jakobwesthoff" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/chrhjoh"><img src="https://avatars.githubusercontent.com/u/80620482?v=4?s=100" width="100px;" alt="Christian Johansen"/><br /><sub><b>Christian Johansen</b></sub></a><br /><a href="#code-chrhjoh" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/VVKot"><img src="https://avatars.githubusercontent.com/u/24480985?v=4?s=100" width="100px;" alt="Volodymyr Kot"/><br /><sub><b>Volodymyr Kot</b></sub></a><br /><a href="#code-VVKot" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://minusfive.com"><img src="https://avatars.githubusercontent.com/u/33695?v=4?s=100" width="100px;" alt="Jorge Villalobos"/><br /><sub><b>Jorge Villalobos</b></sub></a><br /><a href="#code-minusfive" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/TakahiroW4047"><img src="https://avatars.githubusercontent.com/u/33548194?v=4?s=100" width="100px;" alt="Tak"/><br /><sub><b>Tak</b></sub></a><br /><a href="#code-TakahiroW4047" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://eportfolio.dev"><img src="https://avatars.githubusercontent.com/u/98435584?v=4?s=100" width="100px;" alt="Emilio Marin"/><br /><sub><b>Emilio Marin</b></sub></a><br /><a href="#code-e-mar404" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/antigluten"><img src="https://avatars.githubusercontent.com/u/53124465?v=4?s=100" width="100px;" alt="Vladimir Gusev"/><br /><sub><b>Vladimir Gusev</b></sub></a><br /><a href="#code-antigluten" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/FirelightFlagboy"><img src="https://avatars.githubusercontent.com/u/30697622?v=4?s=100" width="100px;" alt="FirelightFlagboy"/><br /><sub><b>FirelightFlagboy</b></sub></a><br /><a href="#code-FirelightFlagboy" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/cameronr"><img src="https://avatars.githubusercontent.com/u/38429?v=4?s=100" width="100px;" alt="Cameron Ring"/><br /><sub><b>Cameron Ring</b></sub></a><br /><a href="#code-cameronr" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/balazsmiklos85"><img src="https://avatars.githubusercontent.com/u/46478889?v=4?s=100" width="100px;" alt="Miklós Balázs"/><br /><sub><b>Miklós Balázs</b></sub></a><br /><a href="#code-balazsmiklos85" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://shortcuts.codes/"><img src="https://avatars.githubusercontent.com/u/20689156?v=4?s=100" width="100px;" alt="Clément Vannicatte"/><br /><sub><b>Clément Vannicatte</b></sub></a><br /><a href="#doc-shortcuts" title="Documentation">📖</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/Meowtomata"><img src="https://avatars.githubusercontent.com/u/95190660?v=4?s=100" width="100px;" alt="Anatoliy"/><br /><sub><b>Anatoliy</b></sub></a><br /><a href="#code-Meowtomata" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/acidsugarx"><img src="https://avatars.githubusercontent.com/u/58903233?v=4?s=100" width="100px;" alt="acidsugarx"/><br /><sub><b>acidsugarx</b></sub></a><br /><a href="#code-acidsugarx" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://jpmelos.com"><img src="https://avatars.githubusercontent.com/u/407407?v=4?s=100" width="100px;" alt="João Sampaio"/><br /><sub><b>João Sampaio</b></sub></a><br /><a href="#code-jpmelos" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://sundar.guru"><img src="https://avatars.githubusercontent.com/u/76529072?v=4?s=100" width="100px;" alt="Sundar Gurumurthy"/><br /><sub><b>Sundar Gurumurthy</b></sub></a><br /><a href="#code-neuroconvergent" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="http://apalermo01.com/"><img src="https://avatars.githubusercontent.com/u/64085614?v=4?s=100" width="100px;" alt="apalermo01"/><br /><sub><b>apalermo01</b></sub></a><br /><a href="#code-apalermo01" title="Code">💻</a></td>
    </tr>
    <tr>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/S1RENS"><img src="https://avatars.githubusercontent.com/u/57037675?v=4?s=100" width="100px;" alt="S1RENS"/><br /><sub><b>S1RENS</b></sub></a><br /><a href="#code-S1RENS" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://caechao.github.io"><img src="https://avatars.githubusercontent.com/u/47220170?v=4?s=100" width="100px;" alt="CaeChao"/><br /><sub><b>CaeChao</b></sub></a><br /><a href="#code-CaeChao" title="Code">💻</a></td>
      <td align="center" valign="top" width="14.28%"><a href="https://github.com/tartansandal"><img src="https://avatars.githubusercontent.com/u/3327775?v=4?s=100" width="100px;" alt="Kahlil Hodgson"/><br /><sub><b>Kahlil Hodgson</b></sub></a><br /><a href="#code-tartansandal" title="Code">💻</a></td>
    </tr>
  </tbody>
</table>

<!-- markdownlint-restore -->
<!-- prettier-ignore-end -->

<!-- ALL-CONTRIBUTORS-LIST:END -->
<!--markdoc_ignore_end-->

## ❤️ Acknowledgement

We would like to thank [epwalsh](https://github.com/epwalsh) for creating this beautiful plugin. If you're feeling especially generous, [he still appreciates some coffee funds!](https://www.buymeacoffee.com/epwalsh).
