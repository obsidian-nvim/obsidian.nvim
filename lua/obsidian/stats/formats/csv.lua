--- CSV formatter. One row per note. Columns chosen to stay flat;
--- multi-valued fields (aliases, tags) are semicolon-joined.
---
--- Output is RFC-4180ish: fields with commas/quotes/newlines get quoted and
--- embedded quotes doubled.

local M = {}

local COLUMNS = {
  "relpath",
  "id",
  "title",
  "words",
  "chars",
  "lines",
  "bytes",
  "headers",
  "blocks",
  "links_out",
  "links_resolved",
  "links_unresolved",
  "links_external",
  "links_anchor",
  "backlinks",
  "has_frontmatter",
  "tags",
  "aliases",
  "mtime",
}

---@param v any
---@return string
local function cell(v)
  if v == nil then return "" end
  local s
  if type(v) == "table" then
    s = table.concat(v, ";")
  elseif type(v) == "boolean" then
    s = v and "true" or "false"
  else
    s = tostring(v)
  end
  if s:find("[,\"\n]") then
    s = '"' .. s:gsub('"', '""') .. '"'
  end
  return s
end

---@param stats obsidian.stats.VaultStats
---@param opts  { columns: string[]|? }
---@return string
function M.render(stats, opts)
  local columns = opts.columns or COLUMNS
  local lines = { table.concat(columns, ",") }
  for _, n in ipairs(stats.notes) do
    local row = {}
    for i, col in ipairs(columns) do
      row[i] = cell(n[col])
    end
    lines[#lines + 1] = table.concat(row, ",")
  end
  return table.concat(lines, "\n")
end

return M
