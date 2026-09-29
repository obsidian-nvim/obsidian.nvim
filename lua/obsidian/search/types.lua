---@class obsidian.search.SortOpts
---
---@field sort_by obsidian.config.SortBy|false|? Defaults to the workspace setting.
---@field sort_reversed boolean|? Defaults to the workspace setting.

---@class obsidian.search.BackendOpts: obsidian.search.SortOpts
---
---@field fixed_strings boolean|?
---@field ignore_case boolean|?
---@field smart_case boolean|?
---@field exclude string[]|? paths to exclude
---@field max_count_per_file integer|?
---@field escape_path boolean|?
---@field include_non_markdown boolean|?

---@class obsidian.search.FindNotesOpts: obsidian.search.SortOpts
---
---@field dir string|obsidian.Path|?
---@field notes obsidian.note.LoadOpts|?
---@field match obsidian.search.NoteMatchOpts|?

---@class obsidian.search.FindAttachmentsOpts: obsidian.search.SortOpts
---
---@field dir string|obsidian.Path|?
