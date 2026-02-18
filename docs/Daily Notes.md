# Daily Notes

[[#Options]]

The Daily Notes feature allows you to quickly create and navigate to date-based notes in your vault. This is useful for journaling, tracking daily tasks, or maintaining a chronological record of your work.

## Commands

### `:Obsidian today` or `:Obsidian today <offset>`

Open today's daily note. You can optionally specify an offset like `:Obsidian today -1` for yesterday or `:Obsidian today +1` for tomorrow.

### `:Obsidian yesterday`

Open yesterday's daily note. Equivalent to `:Obsidian today -1`.

### `:Obsidian tomorrow`

Open tomorrow's daily note. Equivalent to `:Obsidian today +1`.

### `:Obsidian dailies`

Open a picker showing all daily notes in chronological order.

## Usage Examples

### Basic Setup

```lua
require("obsidian").setup {
  daily_notes = {
    enabled = true,
    folder = "daily",
    date_format = "YYYY-MM-DD",
    default_tags = { "journal", "daily" },
  },
}
```

### With Template

```lua
daily_notes = {
  enabled = true,
  folder = "journal",
  template = "daily-note.md",
  default_tags = { "daily" },
}
```

## Notes

- Daily notes are created automatically when you open a date that doesn't have a note yet

## Options

```lua
---@class obsidian.config.DailyNotesOpts

---@field enabled? boolean
---@field folder? string
---@field date_format? string
---@field alias_format? string
---@field template? string
---@field default_tags? string[]
---@field workdays_only? boolean
daily_notes = {
  enabled = true,
  folder = nil,
  date_format = "YYYY-MM-DD",
  alias_format = nil,
  default_tags = { "daily-notes" },
  workdays_only = true,
}
```
