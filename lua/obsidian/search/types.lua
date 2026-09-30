---@class obsidian.BacklinkMatch
---
---@field path string|obsidian.Path The path to the note where the backlinks were found.
---@field line integer The line number (1-indexed) where the backlink was found.
---@field text string The text of the line where the backlink was found.
---@field start integer|? The start of match (0-indexed)
---@field end integer|? The end of match (0-indexed)
---@field link string actual matched link text

---@class obsidian.LinkMatch
---
---@field link string
---@field line integer
---@field start integer 0-indexed
---@field end integer 0-indexed

---@class obsidian.TagLocation
---
---@field tag string The tag found.
---@field note obsidian.Note The note instance where the tag was found.
---@field path string|obsidian.Path The path to the note where the tag was found.
---@field line integer The line number (1-indexed) where the tag was found.
---@field text string The original source line where the tag was found.
---@field range obsidian.Range The exact source range of the tag.
---@field tag_start integer The 1-based byte column where the tag starts.
---@field tag_end integer The 1-based exclusive byte column where the tag ends.

---@class obsidian.Ref
---@field kind "note"|"attachment"|"unresolved"|"tag"
---@field text string
---@field path string|?
---@field note obsidian.Note|?
---@field attachment boolean|?
---@field target string|?
---@field references obsidian.NoteCreationReference[]|?

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
---@field timeout integer|?

---@class obsidian.search.FindAttachmentsOpts: obsidian.search.SortOpts
---
---@field dir string|obsidian.Path|?
---@field timeout integer|?

---@class obsidian.search.FindRefsOpts
---@field dir string|obsidian.Path|?
---@field include_notes boolean|?
---@field include_attachments boolean|?
---@field include_unresolved boolean|?
---@field include_tags boolean|? Reserved until tags are cache-powered.
---@field timeout integer|?

---@class obsidian.search.MatchText
---@field text string

---@class obsidian.search.SubMatch
---@field match obsidian.search.MatchText
---@field start integer
---@field end integer

---@class obsidian.search.MatchData
---@field path obsidian.search.MatchText
---@field lines obsidian.search.MatchText
---@field line_number integer 0-indexed
---@field absolute_offset integer
---@field submatches obsidian.search.SubMatch[]
