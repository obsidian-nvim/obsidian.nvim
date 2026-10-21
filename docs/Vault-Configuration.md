---
title: "Vault Configuration"
tags:
  - configuration
  - vaults
---

Keep vault-specific options in Lua, read compatible settings from the Obsidian app, or explicitly export shared Lua options for app users.

## Obsidian app settings

obsidian.nvim automatically reads supported settings from the app's configuration folder for each workspace. The default folder is `.obsidian`; for another app profile, set `app_settings.config_dir` to its dot-prefixed directory name in `setup()` or workspace `overrides`:

```lua
require("obsidian").setup {
  workspaces = { { path = "~/vaults/work" } },
  app_settings = { config_dir = ".obsidian-work" },
}
```

| App file | Shared settings | Plugin options |
| --- | --- | --- |
| `app.json` | `newFileLocation`, `newFileFolderPath` | `new_notes_location`, `notes_subdir` |
| `app.json` | `attachmentFolderPath` | `attachments.folder` |
| `app.json` | `useMarkdownLinks`, `newLinkFormat`, `alwaysUpdateLinks` | `link.style`, `link.format`, `link.auto_update` |
| `templates.json` | `folder`, `dateFormat`, `timeFormat` | `templates.folder`, `templates.date_format`, `templates.time_format` |
| `daily-notes.json` | `folder`, `format`, `template` | `daily_notes.folder`, `daily_notes.date_format`, `daily_notes.template` |
| `zk-prefixer.json` | `folder`, `format`, `template` | `unique_note.folder`, `unique_note.format`, `unique_note.template` |
| `core-plugins.json` | `templates`, `daily-notes`, `zk-prefixer` | The corresponding `enabled` options |

Shared settings from a valid app file take precedence over explicit Lua options, including workspace overrides. An absent key in that file uses the app's default for the corresponding setting. For example, an empty `templates.json` clears the Lua template folder and selects `YYYY-MM-DD` / `HH:mm`; an empty `app.json` selects vault-root notes and attachments, Wikilinks, shortest link paths, and no automatic link updates.

A missing file leaves its Lua options and plugin defaults unchanged. Each file is handled independently, so a vault can use app settings for attachments and Lua settings for templates. Lua functions, template customizations, substitutions, callbacks, frontmatter rules, and other options without an app equivalent are retained. A vault configured entirely in Lua works without app JSON files. Reading settings never creates or rewrites those files.

App attachment paths `/`, `.`, and `./images` mean the vault root, the note's folder, and a subfolder of the note's folder. A folder such as `.images` is relative to the vault root. Empty daily/unique folders follow the app's default new-note folder; when the app uses the current-folder mode without an active source file, these notes go to the vault root. Daily/unique template paths are resolved from the vault root, independently of Neovim's working directory or the Templates folder.

Modern core-plugin objects use the app's defaults for omitted IDs: Templates and Daily notes are enabled, Unique note creator is disabled. Legacy arrays list the enabled plugins, so an omitted ID is disabled. Invalid or unreadable files produce a warning and fall back to Lua for that file; invalid supported fields use the app's defaults. Other fields are ignored.

Settings are read during setup, workspace selection, and resolution of another workspace's options. Repeat `setup()` or source the vault's `.nvim.lua` to reload settings for the active workspace. App settings are not watched for changes.

The mapping covers the common settings of [Files and links](https://obsidian.md/help/settings), [Templates](https://obsidian.md/help/plugins/templates), [Daily notes](https://obsidian.md/help/plugins/daily-notes), and [Unique note creator](https://obsidian.md/help/plugins/unique-note). Editor appearance, hotkeys, window layout, community-plugin data, and app startup actions have no matching plugin configuration and are not imported. App excluded-file patterns differ from the plugin's gitignore-style filters, and the app's Sync toggle does not configure the plugin's headless sync backend; these settings are not mapped.

## Export app settings

To share a vault configured in Lua with Obsidian app users, apply its configuration and run:

```vim
:Obsidian export_settings
```

The command takes no arguments and exports the selected workspace. Its source is the plugin defaults, the latest options passed to `setup()`, and that workspace's Lua overrides, before app settings are applied. For example, if Lua selects `Templates` and an existing `templates.json` selects `Old templates`, export writes `Templates`. Re-source the vault's `.nvim.lua` first if you have edited it since the last setup.

Export creates or updates `app.json`, `templates.json`, `daily-notes.json`, `zk-prefixer.json`, and `core-plugins.json` inside the workspace's `app_settings.config_dir` (default `.obsidian`). It writes all shared fields listed in the table above, including normalized plugin defaults and the enabled state of Templates, Daily notes, and Unique note creator. Existing mapped values are replaced; unrelated keys, other core-plugin states, and the object/array form of `core-plugins.json` are preserved. JSON formatting may change. Other app files and the Lua configuration are left untouched. Export does not copy template content; keep the referenced templates and folders in the shared vault.

Paths are stored relative to the vault. Relative daily/unique template names are resolved against the Lua Templates folder; absolute template paths inside the vault are also supported. Exported template paths include the `.md` extension so the app can validate them in its settings UI; Lua template names can still omit it. An omitted `daily_notes.folder` inherits `notes_subdir`, matching daily note creation in Neovim. An explicitly empty daily folder and an omitted or empty unique folder are written as `/` to retain the vault root instead of inheriting the app's new-note folder. Attachment paths preserve `/`, `.`, and `./images` semantics. The command reloads the selected workspace after a successful export, so subsequent plugin operations use the generated app settings.

Only representable shared values are exported. Date/time formats must be nonempty Moment-style strings (`DD-MM-YYYY`, `HH:mm`); strftime formats and a function-valued `unique_note.format` stop the export. Paths outside the vault and a Templates folder equal to the vault root also stop it. Lua naming functions, template customizations, substitutions, callbacks, frontmatter rules, and other plugin-only settings are neither executed nor serialized.

All existing target files and exported values are validated before writing. Malformed or unreadable JSON stops the export without replacing files. The output is staged in temporary files in the configuration directory before each destination is replaced atomically. If a replacement fails, the error identifies that file; earlier replacements may already have succeeded. Export runs only on this explicit command. If the Obsidian app is open, close the vault before exporting and reopen it afterward so it loads the generated settings.

## Vault-local Lua configuration

You can keep a vault's settings in a `.nvim.lua` file at its root using Neovim's standard `exrc` option (`:h 'exrc'`). Enable `vim.opt.exrc = true` in your Neovim configuration and make sure obsidian.nvim is available on `runtimepath` before the local file is sourced. For example, a plugin manager configuration that loads obsidian.nvim only on `FileType` will need to load it earlier.

```lua
-- .nvim.lua in the vault root
local source = debug.getinfo(1, "S").source:gsub("^@", "")
local buffer = source:match("^:source buffer=(%d+)$")
if buffer then
  source = vim.api.nvim_buf_get_name(tonumber(buffer))
end
local root = vim.fs.dirname(vim.fs.normalize(source))

require("obsidian").setup {
  workspaces = {
    { name = vim.fs.basename(root), path = root },
  },
  notes_subdir = "notes",
  new_notes_location = "notes_subdir",
  templates = {
    folder = "templates",
  },
}
```

Start Neovim with the vault root as its working directory and approve the local file through Neovim's trust prompt. Choose `view`, inspect the file, and run `:trust` in its buffer. Trust is tied to the file's contents; after editing and saving it, run `:trust` again to allow automatic loading on the next startup. Paths in this example are resolved from the `.nvim.lua` file, so notes in nested folders use the same vault settings. The local file accepts the regular plugin options, including Lua functions and callbacks.

Calling `setup()` again replaces the previous options and workspace list, updates the current note, and removes the previous configuration's buffer handlers, LSP clients, cache, footer, UI marks, and pending sync timers. Include any shared options you want to retain in each call. Invalid options are reported without replacing a working configuration.

`exrc` loads local configuration at startup based on the working directory; opening a note from an unrelated directory or switching between vault buffers does not automatically source that vault's `.nvim.lua`. To apply or reload a vault's settings in an existing session, explicitly run `:source /path/to/vault/.nvim.lua`, or `:source` while editing that file. The example handles both filenames and Neovim 0.11 buffer-source labels; reloading retains the vault root. For automatic switching among a known list of vaults, use the existing `workspaces` and workspace `overrides` options.

## Vault-specific note creation

The [complete vault-local example](https://github.com/obsidian-nvim/obsidian.nvim/blob/main/examples/vault.lua) uses ordinary plugin options and Lua functions. Copy it to `.nvim.lua` in the vault root and adjust the folders and naming rules. No custom JSON file or conversion layer is needed.

Set both `notes_subdir` and `new_notes_location = "notes_subdir"` to place ordinary notes in that folder instead of the current note's folder. Templates without a customization use the same folder and global `note_id_func`. The example preserves manually entered names and uses a timestamp when the name is empty.

Use `templates.customizations` for template-specific folders and names:

```lua
customizations = {
  ["daily-plan"] = {
    notes_subdir = "Personal/Schedule Daily",
    note_id_func = function()
      return "SD - " .. os.date "%d-%m-%Y"
    end,
  },
}
```

Place this table inside `templates`. Keys match the template's filename stem, without `.md`, case-insensitively. A matching customization uses `notes_subdir`; omitted folders and naming functions fall back to the workspace options. Avoid duplicate template stems in different subfolders when using customizations.

The naming function above always uses the date, even if a title was entered. To preserve manual names for this template, accept `title` and return `title or ("SD - " .. os.date "%d-%m-%Y")` instead. A path entered explicitly, such as `Projects/My note`, chooses the folder before the naming function runs. These rules apply when creating notes with `new`, `new_from_template`, or a default `note.template`; inserting a template into an existing note does not move or rename it.

Template and daily-note date formats use Moment-style tokens such as `DD-MM-YYYY`; the example's naming functions call Lua's `os.date` and therefore use `%d-%m-%Y`. Existing app JSON settings still take priority for shared fields, including the ordinary note folder. Template customizations and naming functions have no core-app equivalent and remain local Lua rules.

## See also

[[Workspace]] · [[Template]] · [[Daily-Notes]] · [[Unique-Note]] · [[Attachment]]
