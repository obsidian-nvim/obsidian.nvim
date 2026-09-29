local Document = require "obsidian.parse.document"
local Range = require "obsidian.range"
local parse_refs = require "obsidian.parse.refs"

local M = {}

---Extract outgoing wiki and Markdown links from one source line.
---@param line string
---@param lnum integer 1-based
---@param document obsidian.parse.Document
---@return table[]
function M.extract_line(line, lnum, document)
  local out = {}
  for _, ref in ipairs(parse_refs.extract(line, { row = lnum - 1, lexical = true })) do
    local origin = Range.new(lnum - 1, ref.range.start_col, lnum - 1, ref.range.start_col + 1)
    if
      (ref.kind == "wiki" or ref.kind == "markdown")
      and not document:intersects(origin, Document.INLINE_EXCLUSIONS)
      and not document:intersects(ref.range, Document.COMMENTS)
    then
      out[#out + 1] = {
        kind = ref.kind,
        raw = ref.raw,
        target = ref.target,
        label = ref.label,
        anchor = ref.anchor,
        block = ref.block,
        embed = ref.embed,
        line = lnum,
        col = ref.range.start_col + 1,
      }
    end
  end
  return out
end

---Extract every outgoing link from a file, preserving duplicate locations.
---@param path string
---@return table[]
function M.from_file(path)
  local lines = {}
  for line in io.lines(path) do
    lines[#lines + 1] = line:gsub("\r$", "")
  end
  local document = Document.parse(lines)
  local out = {}
  for lnum, line in ipairs(lines) do
    vim.list_extend(out, M.extract_line(line, lnum, document))
  end
  return out
end

return M
