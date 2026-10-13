---
title: "Daily Notes"
tags:
  - core-plugins
  - notes
---

- [Commands](#commands)
- [Usage Examples](#usage-examples)
- [Notes](#notes)
- [Options](#options)
- [See also](#see-also)

The Daily Notes feature allows you to quickly create and navigate to date-based notes in your vault. This is useful for journaling, tracking daily tasks, or maintaining a chronological record of your work.

## Commands

### `:Obsidian daily [DATE]`

Open or create today's daily note, or a specific date. `DATE` can be an integer calendar-day offset (`+1`, `-1`), `today`, `tomorrow`, `yesterday`, or a formatted date such as `2026-06-25`. Multi-word dates are passed in full to a custom `resolvers.date_parse` (see [[Resolvers]]). `tomorrow` and `yesterday` skip weekends when `workdays_only` is enabled; offsets and explicit dates do not.

### `:Obsidian dailies [OFFSET [OFFSET]]`

Open a picker showing dates from five days ago through today, including notes that do not exist yet. One integer offset picks between that day and today; two offsets pick between those days, regardless of order. For example, `:Obsidian dailies -2 1` shows two days ago through tomorrow. Selecting a missing note creates it.

The older `:Obsidian today`, `:Obsidian tomorrow`, and `:Obsidian yesterday` commands still work when invoked explicitly, but are hidden from the command picker and subcommand completion. They will be removed in 4.0; see [[Breaking-Changes#daily-notes-command-redesign]].

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

### Date format

Adding slash in daily formats will automatically create subdirectories:

```lua
daily_notes = {
  date_format = "YYYY/MM/DD",
}
```

Will create notes in path `daily_notes.folder/year/month/day.md`.

For weekly folders that start on Sunday, set `start_of_week = 0`. This adjusts the Moment-style week tokens `W`, `WW`, `Wo`, `GG`, and `GGGG` without changing the daily date:

```lua
daily_notes = {
  date_format = "GGGG-[W]WW/YYYY-MM-DD",
  start_of_week = 0,
}
```

## Notes

- Daily notes are created automatically when you open a date that doesn't have a note yet
- `workdays_only` changes the meaning of `tomorrow` and `yesterday`, not numeric offsets or explicit dates

## Options

```lua
---@class obsidian.config.DailyNotesOpts
---
---@field enabled? boolean
---@field folder? string
---@field date_format? string
---@field alias_format? string
---@field template? string
---@field default_tags? string[]
---@field workdays_only? boolean
---@field start_of_week? integer 0 is Sunday, 1 is Monday, ..., 6 is Saturday.
daily_notes = {
  enabled = true,
  folder = nil,
  date_format = "YYYY-MM-DD",
  alias_format = nil,
  default_tags = { "daily-notes" },
  workdays_only = true,
  start_of_week = 1, -- Monday
}
```

## See also

[[Template]] · [[Workspace]] · [[Note]]
