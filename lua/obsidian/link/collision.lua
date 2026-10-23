local api = require "obsidian.api"
local Document = require "obsidian.parse.document"
local Note = require "obsidian.note"
local log = require "obsidian.log"
local refs = require "obsidian.parse.refs"
local uri = require "obsidian.uri"
local Range = require "obsidian.range"

local M = {}

local function paths_in_workspace(workspace)
  local root = tostring(workspace.root)
  return vim.fs.find(function(name, dir)
    return vim.endswith(name, ".md") and api.path_is_note(vim.fs.joinpath(dir, name), workspace)
  end, { path = root, type = "file", limit = math.huge })
end

local function candidate_paths(paths, stem)
  local candidates = {}
  if vim.fn.executable "rg" == 1 then
    local root = paths[1] and tostring(api.resolve_workspace_dir(paths[1]))
    if root then
      local args = {
        "rg",
        "--files-with-matches",
        "--fixed-strings",
        "--ignore-case",
        "--hidden",
        "--no-ignore",
        "--glob",
        "*.md",
        "--regexp",
        stem,
      }
      local encoded = uri.encode(stem)
      if encoded ~= stem then
        vim.list_extend(args, { "--regexp", encoded })
      end
      vim.list_extend(args, { "--", root })
      local matches = vim.fn.systemlist(args)
      if vim.v.shell_error > 1 then
        log.warn("Could not search for link collisions in '%s'", root)
        return nil
      end
      for _, path in ipairs(matches) do
        candidates[vim.fs.normalize(path)] = true
      end
    end
  else
    local encoded = uri.encode(stem):lower()
    for _, path in ipairs(paths) do
      for _, line in ipairs(vim.fn.readfile(path)) do
        if line:lower():find(stem:lower(), 1, true) or line:lower():find(encoded, 1, true) then
          candidates[path] = true
          break
        end
      end
    end
  end
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(bufnr) and vim.bo[bufnr].modified then
      local path = vim.fs.normalize(vim.api.nvim_buf_get_name(bufnr))
      if path and path ~= "" then
        candidates[path] = true
      end
    end
  end
  return candidates
end

---@param paths string[]
---@param excluded string?
---@param added string?
---@return string[]
local function snapshot(paths, excluded, added)
  ---@type string[]
  local result = {}
  for _, path in ipairs(paths) do
    path = vim.fs.normalize(path)
    if path ~= excluded then
      result[#result + 1] = path
    end
  end
  if added and not vim.tbl_contains(result, added) then
    result[#result + 1] = added
  end
  return result
end

---@param target string
---@param source string
---@param paths string[]
---@param root string
---@param ids table<string, string[]|false>
---@return string?
---@return boolean unique
local function resolve_short(target, source, paths, root, ids)
  local name = vim.endswith(target, ".md") and target or target .. ".md"
  local by_path = {}
  for _, path in ipairs(paths) do
    by_path[path] = true
  end
  local local_path = vim.fs.normalize(vim.fs.joinpath(vim.fs.dirname(source), name))
  local root_path = vim.fs.normalize(vim.fs.joinpath(root, name))
  if by_path[local_path] then
    return local_path, true
  elseif by_path[root_path] then
    return root_path, true
  end

  local matching = {}
  for _, path in ipairs(paths) do
    if ids[path] == nil then
      local bufnr = vim.fn.bufnr(path)
      local loaded = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
      local ok, note = pcall(function()
        if loaded then
          return Note.from_buffer(bufnr, { max_lines = Obsidian.opts.search.max_lines })
        end
        return Note.from_file(path, { max_lines = Obsidian.opts.search.max_lines })
      end)
      ids[path] = ok and note:reference_ids { lowercase = true } or false
    end
    if ids[path] == false then
      return nil, false
    end
    if vim.list_contains(ids[path], target:lower()) then
      matching[#matching + 1] = path
      if #matching > 1 then
        return nil, false
      end
    end
  end
  return matching[1], #matching == 1
end

local function target_start(ref)
  if ref.kind == "wiki" then
    local bracket = ref.raw:find("[[", 1, true)
    return bracket and ref.range.start_col + bracket + 1 or nil
  elseif ref.kind == "markdown" then
    local bracket = ref.raw:find("](", 1, true)
    return bracket and ref.range.start_col + bracket + 1 or nil
  end
end

local function target_text(ref, old_path, root)
  local rel = old_path:sub(#root + 2)
  if ref.kind == "wiki" then
    rel = rel:gsub("%.md$", "")
    if ref.target:find "%%[%x][%x]" then
      rel = uri.encode(rel, { keep_path_sep = true })
    end
  else
    rel = uri.encode(rel, { keep_path_sep = true })
  end
  return "/" .. rel
end

---@class obsidian.link.CollisionPlan
---@field edits table<string, lsp.TextEdit[]>
---@field original table<string, { row: integer, col: integer, text: string }[]>
---@field count integer
---@field notes integer
---@field unresolved integer
---@field root string

---Plan target-only edits using the source note's before/after path resolution.
---The new file may already exist (creation) or be a hypothetical rename target.
---@param path string
---@return string[]? paths
function M.capture(path)
  local workspace = api.find_workspace(path)
  if not workspace or not vim.endswith(path, ".md") then
    return nil
  end
  local name = vim.fs.basename(path):lower()
  local other = vim.fs.find(function(entry, dir)
    return entry:lower() == name and api.path_is_note(vim.fs.joinpath(dir, entry), workspace)
  end, { path = tostring(workspace.root), type = "file", limit = 1 })
  return #other > 0 and paths_in_workspace(workspace) or nil
end

---@param opts { new_path: string, old_path: string?, before_paths: string[]? }
---@return obsidian.link.CollisionPlan?
function M.plan(opts)
  local new_path = vim.fs.normalize(opts.new_path)
  local old_path = opts.old_path and vim.fs.normalize(opts.old_path) or nil
  local workspace = api.find_workspace(new_path)
  if not workspace or not vim.endswith(new_path, ".md") then
    return nil
  end
  local root = tostring(workspace.root)
  local stem = vim.fs.basename(new_path):gsub("%.md$", "")
  local other = vim.fs.find(function(name, dir)
    return name:lower() == (stem .. ".md"):lower()
      and api.path_is_note(vim.fs.joinpath(dir, name), workspace)
      and vim.fs.normalize(vim.fs.joinpath(dir, name)) ~= (old_path or new_path)
  end, { path = root, type = "file", limit = 1 })
  if #other == 0 then
    return nil
  end

  local all = paths_in_workspace(workspace)
  ---@type table<string, string[]|false>
  local ids = {}
  ---@type string[]
  local before = opts.before_paths and snapshot(opts.before_paths) or snapshot(all, new_path, old_path)
  local after = snapshot(all, old_path, new_path)
  local collisions = 0
  for _, path in ipairs(after) do
    if tostring(vim.fs.basename(path)):lower() == (stem .. ".md"):lower() then
      collisions = collisions + 1
    end
  end
  if collisions < 2 then
    return nil
  end

  ---@type obsidian.link.CollisionPlan
  local plan = { edits = {}, original = {}, count = 0, notes = 0, unresolved = 0, root = root }
  local candidates = candidate_paths(all, stem)
  if not candidates then
    return nil
  end
  for _, path in ipairs(all) do
    if candidates[path] and (path ~= new_path or old_path) then
      local bufnr = vim.fn.bufnr(path)
      local loaded = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
      local lines = loaded and vim.api.nvim_buf_get_lines(bufnr, 0, -1, false) or vim.fn.readfile(path)
      local document = Document.parse(lines)
      for row, line in ipairs(lines) do
        for _, ref in ipairs(refs.extract(line, { row = row - 1, lexical = true })) do
          local target = vim.uri_decode(ref.target)
          local simple = ref.kind == "wiki" or ref.kind == "markdown"
          local same_stem = target:lower() == stem:lower() or target:lower() == (stem .. ".md"):lower()
          if simple and same_stem and not target:find("/", 1, true) then
            local origin = Range.new(row - 1, ref.range.start_col, row - 1, ref.range.start_col + 1)
            if not document:intersects(origin, Document.INLINE_EXCLUSIONS) then
              -- A case-folded filename match is not proof of identical resolution
              -- on filesystems whose case behavior we cannot determine here.
              local target_stem = target:gsub("%.md$", "")
              if target_stem ~= stem then
                plan.unresolved = plan.unresolved + 1
              else
                local prior, unique = resolve_short(target, path, before, root, ids)
                if unique and prior and prior ~= new_path then
                  local current = resolve_short(target, path, after, root, ids)
                  if current ~= prior then
                    local col = target_start(ref)
                    if col then
                      local new_text = target_text(ref, prior, root)
                      plan.edits[path] = plan.edits[path] or {}
                      plan.original[path] = plan.original[path] or {}
                      plan.edits[path][#plan.edits[path] + 1] = {
                        range = {
                          start = { line = row - 1, character = col },
                          ["end"] = { line = row - 1, character = col + #ref.target },
                        },
                        newText = new_text,
                      }
                      plan.original[path][#plan.original[path] + 1] = { row = row - 1, col = col, text = ref.target }
                      plan.count = plan.count + 1
                    end
                  end
                elseif not unique then
                  plan.unresolved = plan.unresolved + 1
                end
              end
            end
          end
        end
      end
      if plan.edits[path] then
        plan.notes = plan.notes + 1
      end
    end
  end
  return plan
end

---Queue a successful note creation after its final write. Only creations with a
---pre-write filename collision carry a snapshot and need a reference search.
---@param new_path string
---@param before_paths string[]?
function M.created(new_path, before_paths)
  if not before_paths then
    return
  end
  require("obsidian.link.queue").run(new_path, function(done)
    local apply = require "obsidian.link.collision_apply"
    local opts = { new_path = new_path, before_paths = before_paths }
    local plan = M.plan(opts)
    if plan and (plan.count > 0 or plan.unresolved > 0) and apply.confirm(plan) then
      local fresh = M.plan(opts)
      if fresh and not vim.deep_equal(plan.edits, fresh.edits) then
        plan = fresh
        if Obsidian.opts.link.auto_update ~= true and not apply.confirm(plan) then
          return done()
        end
      end
      if plan then
        apply.apply(plan)
      end
    end
    done()
  end)
end

return M
