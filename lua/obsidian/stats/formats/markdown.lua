--- Markdown formatter. Human-readable report.

local M = {}

---@param stats obsidian.stats.VaultStats
---@param opts  table
---@return string
function M.render(stats, opts)
  _ = opts
  local lines = {}
  local function put(s) lines[#lines + 1] = s end

  put("# Vault stats")
  put("")
  put(("- **Dir**: `%s`"):format(stats.vault.dir))
  put(("- **Notes**: %d"):format(stats.vault.note_count))
  put(("- **Scan**: %dms"):format(stats.vault.scan_ms))
  put("")

  local a = stats.aggregate
  put("## Totals")
  put(("- Words: %d  |  Chars: %d  |  Lines: %d  |  Bytes: %d"):format(a.words, a.chars, a.lines, a.bytes))
  put(("- Internal links: %d (resolved %d, unresolved %d)"):format(a.links_out, a.links_resolved, a.links_unresolved))
  put(("- External URIs: %d  |  In-note anchors: %d"):format(a.links_external, a.links_anchor))
  put(("- With frontmatter: %d  |  Without: %d"):format(a.with_frontmatter, a.without_frontmatter))
  put(("- Orphans (no backlinks): %d  |  Leafs (no outbound): %d"):format(a.orphans, a.leafs))
  put(("- Unique tags: %d"):format(a.tags))
  put("")

  local sup = stats.superlatives
  if sup.most_words then
    put("## Superlatives")
    put(("- **Most words**: `%s` (%d)"):format(sup.most_words.relpath, sup.most_words.words))
    if sup.fewest_words then
      put(("- **Fewest words**: `%s` (%d)"):format(sup.fewest_words.relpath, sup.fewest_words.words))
    end
    if sup.most_links then
      put(("- **Most links out**: `%s` (%d)"):format(sup.most_links.relpath, sup.most_links.links_out))
    end
    if sup.most_backlinks then
      put(("- **Most backlinks**: `%s` (%d)"):format(sup.most_backlinks.relpath, sup.most_backlinks.backlinks))
    end
    if sup.largest then
      put(("- **Largest file**: `%s` (%d bytes)"):format(sup.largest.relpath, sup.largest.bytes))
    end
    put("")
  end

  if #stats.tags > 0 then
    put("## Top tags")
    for i, t in ipairs(stats.tags) do
      if i > 20 then break end
      put(("- `#%s` &mdash; %d"):format(t.tag, t.count))
    end
    put("")
  end

  if #stats.unresolved_links > 0 then
    put(("## Unresolved links (%d)"):format(#stats.unresolved_links))
    for i, u in ipairs(stats.unresolved_links) do
      if i > 50 then
        put(("- ...and %d more"):format(#stats.unresolved_links - 50))
        break
      end
      put(("- `%s:%d` -> `%s`"):format(u.relpath, u.line, u.link))
    end
    put("")
  end

  for _, topic in ipairs(stats.topics) do
    put(("## Topic: %s  (%d notes)"):format(topic.name, topic.aggregate.notes))
    put(("- Words: %d  |  Links: %d  |  Unresolved: %d"):format(
      topic.aggregate.words, topic.aggregate.links_out, topic.aggregate.links_unresolved
    ))
    put("")
  end

  return table.concat(lines, "\n")
end

return M
