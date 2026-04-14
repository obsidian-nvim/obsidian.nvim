---Cursor position within a completion request.
---@class obsidian.completion.sources.base.Request.Context.Cursor
---@field public row integer 1-indexed line number
---@field public line integer 1-indexed line number (same as row, used by tags for frontmatter)
---@field public character integer 0-indexed byte offset into the line (utf-8)

---A request context class that partially matches cmp.Context to serve as a common interface for completion sources
---@class obsidian.completion.sources.base.Request.Context
---@field public bufnr integer
---@field public cursor obsidian.completion.sources.base.Request.Context.Cursor
---@field public cursor_after_line string
---@field public cursor_before_line string

---A request class that partially matches cmp.Request to serve as a common interface for completion sources
---@class obsidian.completion.sources.base.Request
---@field public context obsidian.completion.sources.base.Request.Context
