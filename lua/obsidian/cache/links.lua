local resolver = require "obsidian.link.resolver"
local util = require "obsidian.util"

local M = {}

---@class obsidian.cache.LinkReference
---@field filename string
---@field lnum integer
---@field col integer
---@field raw string

---@class obsidian.cache.UnresolvedLink
---@field target string
---@field kind "note"|"attachment"|"file"
---@field predicted_path? string
---@field references obsidian.cache.LinkReference[]
---@field resolution obsidian.link.Resolution

---@return table<string, table>
local function cached_attachments()
  local cache = require "obsidian.cache"
  local attachments = rawget(cache, "attachments")
  if attachments and attachments.all then
    return attachments.all()
  end
  return {}
end

---@return obsidian.link.Index
function M.index()
  local cache = require "obsidian.cache"
  return resolver.build_index(cache.notes.all(), cached_attachments())
end

--- Resolve a target against the current cache using the canonical link policy.
---@param location string
---@param opts obsidian.link.ResolveOpts|?
---@return obsidian.link.Resolution
function M.resolve(location, opts)
  opts = vim.tbl_extend("force", {}, opts or {}, { index = M.index() })
  return resolver.resolve_from_index(resolver.parse_target(location, opts), opts)
end

---@param opts { dir: string|obsidian.Path|?, include_attachments: boolean|?, include_files: boolean|? }|?
---@return obsidian.cache.UnresolvedLink[]
function M.unresolved(opts)
  opts = opts or {}
  local cache = require "obsidian.cache"
  local notes = cache.notes.all()
  local index = resolver.build_index(notes, cached_attachments())
  local dir = opts.dir and vim.fs.normalize(tostring(opts.dir)) or nil
  local grouped = {}
  local resolved_targets = {}

  for source_path, note in pairs(notes) do
    for _, outgoing in ipairs(note.links_out or {}) do
      local target = resolver.parse_target(outgoing.target or "", { link_type = outgoing.kind })
      if
        target.kind ~= "external"
        and target.kind ~= "local_fragment"
        and target.kind ~= "invalid"
        and (opts.include_attachments ~= false or target.kind ~= "attachment")
        and (opts.include_files == true or target.kind ~= "file")
      then
        local source_scope = ""
        if
          (target.kind == "file" and not target.vault_relative)
          or (target.kind == "attachment" and not target.vault_relative and (target.normalized:find("/", 1, true) or vim.startswith(
            Obsidian.opts.attachments.folder or "",
            "."
          )))
          or (
            target.kind == "note"
            and not target.vault_relative
            and Obsidian.opts.new_notes_location == "current_dir"
            and not target.normalized:find("/", 1, true)
          )
        then
          source_scope = vim.fs.dirname(source_path)
        end
        local resolution_key = table.concat({ target.kind, target.normalized:lower(), source_scope }, "\0")
        local result = resolved_targets[resolution_key]
        if not result then
          result = resolver.resolve_from_index(target, {
            source_path = source_path,
            index = index,
          })
          resolved_targets[resolution_key] = result
        end
        if
          result.status == "missing"
          and (not dir or (result.predicted_path and util.is_subpath(result.predicted_path, dir)))
        then
          local key = result.predicted_path or (target.kind .. ":" .. target.normalized:lower())
          local unresolved = grouped[key]
          if not unresolved then
            unresolved = {
              target = target.normalized,
              kind = target.kind,
              predicted_path = result.predicted_path,
              references = {},
              resolution = result,
            }
            grouped[key] = unresolved
          end
          unresolved.references[#unresolved.references + 1] = {
            filename = source_path,
            lnum = outgoing.line or 1,
            col = outgoing.col or 1,
            raw = outgoing.raw or outgoing.target,
          }
        end
      end
    end
  end

  local unresolved = vim.tbl_values(grouped)
  table.sort(unresolved, function(a, b)
    if a.target ~= b.target then
      return a.target:lower() < b.target:lower()
    end
    return (a.predicted_path or "") < (b.predicted_path or "")
  end)
  for _, item in ipairs(unresolved) do
    table.sort(item.references, function(a, b)
      if a.filename ~= b.filename then
        return a.filename < b.filename
      elseif a.lnum ~= b.lnum then
        return a.lnum < b.lnum
      else
        return a.col < b.col
      end
    end)
  end
  return unresolved
end

return M
