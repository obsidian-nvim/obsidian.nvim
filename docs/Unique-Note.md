[Options](#Options)

## Unique Note

This feature creates notes with timestamp-based unique IDs, compatible with the [Obsidian Unique Note plugin](https://help.obsidian.md/plugins/unique-note).

When a note ID collision is detected (a note with the same name already exists), the plugin automatically increments the timestamp by the smallest time unit present in the format string. For example:

- If format is `"YYYYMMDD-HHmmss"`, increment by 1 second
- If format is `"YYYYMMDDHHmm"`, increment by 1 minute
- If format is `"YYYYMMDD"`, increment by 1 day

## Format

`opts.unique_note.format` defaults to `"YYYYMMDDHHmm"`. This uses the [moment.js format](https://momentjs.com/docs/#/displaying/format/) to generate note IDs. Common patterns:

- `YYYYMMDD` - Date only (e.g., `20240307`)
- `YYYYMMDDHHmm` - Date and time to minute (e.g., `202403071430`)
- `YYYYMMDD-HHmmss` - Date and time to second with separator (e.g., `20240307-143001`)

## Folder

`opts.unique_note.folder` optionally specifies a subfolder within the vault to create unique notes in. If not set, notes are created in the vault root.

## Template

`opts.unique_note.template` optionally specifies a template to use when creating unique notes. The template follows the same syntax as other note templates in the plugin.

## Usage

The unique note feature is exposed via the `:Obsidian unique_note` command:

```vim
" Create a unique note with current timestamp
:Obsidian unique_note
```

There's an additional action exposed via lua function, to insert a unique link at cursor:

```vim
:lua require"obsidian.actions".unique_link()
```

## Options

```lua
---@class obsidian.config.UniqueNoteOpts
---@field enabled? boolean
---@field format? string
---@field folder? string
---@field template? string
unique_note = {
  enabled = true,
  format = "YYYYMMDDHHmm",
  folder = nil,
  template = nil,
}
```
