---@class obsidian.parse.line.LineOpts
---@field row integer? 0-based row; defaults to 0 for line-relative ranges.
---@field lexical boolean? return lexical matches without standalone document filtering.

---@class obsidian.parse.line.Match
---@field raw string Matched source text.
---@field range obsidian.Range 0-based, end-exclusive byte range.

return {}
