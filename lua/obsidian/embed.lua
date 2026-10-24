local search = require "obsidian.search"
local ts = require "obsidian.ts"
local watchfiles = require "obsidian.lsp.watchfiles"

local M = {}

local ns_id = vim.api.nvim_create_namespace "obsidian-nvim-embeds"
local LEFT_SEP = "▏"

---@class obsidian.embed.Context
---@field path string|nil
---@field note obsidian.Note

---@class obsidian.embed.State
---@field buf integer
---@field group integer
---@field dependencies table<string, boolean>
---@field source_path string|nil

---@class obsidian.embed.Match
---@field col integer 0-indexed
---@field target string

---@type table<integer, obsidian.embed.State>
local states = {}

---@type table<string, table[]>
local note_cache = {}

local unregister_watchfiles
local watch_refresh_pending = {}

local markdown_extensions = {
  md = true,
  markdown = true,
  qmd = true,
}

---@param path string
---@return string
local function normalize(path)
  return vim.fs.normalize(path)
end

---@param path string
---@return string
local function extension(path)
  return (path:match "%.([^./\\]+)$" or ""):lower()
end

---@param target string
---@return boolean
local function is_markdown(target)
  local ext = extension(target)
  return ext == "" or markdown_extensions[ext] == true
end

---@param line table[]
---@return table[]
local function with_separator(line)
  table.insert(line, 1, { LEFT_SEP, "NonText" })
  return line
end

---@param note obsidian.Note
---@return string[]
local function note_body(note)
  local lines = {}
  local start_line = note.frontmatter_end_line and note.frontmatter_end_line + 1 or 1
  for line_num = start_line, #note.contents do
    lines[#lines + 1] = note.contents[line_num]
  end
  return lines
end

---@param context obsidian.embed.Context
---@return table[]
local function render_note(context)
  local cache_key = context.path and normalize(context.path)
  if cache_key and note_cache[cache_key] then
    return note_cache[cache_key]
  end

  local virt_lines = ts.to_virt_lines(note_body(context.note))
  for _, line in ipairs(virt_lines) do
    with_separator(line)
  end
  if cache_key then
    note_cache[cache_key] = virt_lines
  end
  return virt_lines
end

---@param body string
---@return string
local function clean_wiki_target(body)
  return vim.trim(body:match "^([^|]+)" or body)
end

---@param body string
---@return string
local function clean_markdown_target(body)
  body = vim.trim(body)
  body = body:match "^<(.+)>$" or body
  body = body:match "^(%S+)%s+['\"].-['\"]$" or body
  return vim.uri_decode(body:gsub("\\ ", " "))
end

---@param line string
---@return obsidian.embed.Match[]
local function find_embeds(line)
  local matches = {}
  for col, body in line:gmatch "()!%[%[([^%]]+)%]%]" do
    matches[#matches + 1] = {
      col = col - 1,
      target = clean_wiki_target(body),
    }
  end
  for col, body in line:gmatch "()!%[[^%]]*%]%(([^%)]+)%)" do
    matches[#matches + 1] = {
      col = col - 1,
      target = clean_markdown_target(body),
    }
  end
  table.sort(matches, function(left, right)
    return left.col < right.col
  end)
  return matches
end

---@param target string
---@return string
local function target_without_fragment(target)
  return (target:gsub("#.*$", ""):gsub("%?.*$", ""))
end

---@param match obsidian.embed.Match
---@return obsidian.embed.Context|nil
local function resolve_context(match)
  local target = target_without_fragment(match.target)
  if not is_markdown(target) then
    return nil
  end

  local ok, notes = pcall(search.resolve_note, target, {})
  if not ok or not notes or not notes[1] then
    return nil
  end
  local note = notes[1]
  ---@cast note -nil

  return {
    path = note.path and normalize(tostring(note.path)) or nil,
    note = note,
  }
end

---@param path string|nil
local function invalidate(path)
  if path then
    note_cache[normalize(path)] = nil
  end
end

local function prune_cache()
  local active = {}
  for _, state in pairs(states) do
    for path in pairs(state.dependencies) do
      active[path] = true
    end
  end
  for path in pairs(note_cache) do
    if not active[path] then
      note_cache[path] = nil
    end
  end
end

---@param buf integer
local function queue_watch_refresh(buf)
  if watch_refresh_pending[buf] then
    return
  end
  watch_refresh_pending[buf] = true
  vim.schedule(function()
    watch_refresh_pending[buf] = nil
    if states[buf] then
      M.refresh(buf)
    end
  end)
end

---@param events table[]
local function on_watchfiles(events)
  local refresh_all = false
  local changed_paths = {}

  for _, event in ipairs(events) do
    for _, key in ipairs { "path", "old_path", "new_path" } do
      local path = event[key]
      if path then
        path = normalize(path)
        changed_paths[path] = true
        invalidate(path)
      end
    end
    if event.type == "created" or event.type == vim.lsp.protocol.FileChangeType.Created or event.type == "renamed" then
      refresh_all = true
    end
  end

  for buf, state in pairs(states) do
    local affected = refresh_all or (state.source_path and changed_paths[state.source_path])
    if not affected then
      for path in pairs(changed_paths) do
        if state.dependencies[path] then
          affected = true
          break
        end
      end
    end
    if affected then
      queue_watch_refresh(buf)
    end
  end
end

local function ensure_watchfiles_handler()
  if not unregister_watchfiles then
    unregister_watchfiles = watchfiles.register_handler(on_watchfiles)
  end
end

---@param buf integer
M.refresh = function(buf)
  local state = states[buf]
  if not state or not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  state.source_path = vim.api.nvim_buf_get_name(buf)
  state.source_path = state.source_path ~= "" and normalize(state.source_path) or nil
  state.dependencies = {}
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for line_num, line in ipairs(lines) do
    local rendered = {}
    for _, match in ipairs(find_embeds(line)) do
      local context = resolve_context(match)
      if context then
        if context.path then
          state.dependencies[normalize(context.path)] = true
        end
        local ok, virt_lines = pcall(render_note, context)
        if ok and virt_lines then
          vim.list_extend(rendered, virt_lines)
        end
      end
    end

    if #rendered > 0 then
      vim.api.nvim_buf_set_extmark(buf, ns_id, line_num - 1, 0, {
        virt_lines = rendered,
      })
    end
  end
  prune_cache()
end

---@param buf integer
M.attach = function(buf)
  if not vim.api.nvim_buf_is_valid(buf) or not vim.api.nvim_buf_is_loaded(buf) then
    return
  end

  local state = states[buf]
  if state then
    M.refresh(buf)
    return
  end

  state = {
    buf = buf,
    group = vim.api.nvim_create_augroup("obsidian.embed." .. buf, { clear = true }),
    dependencies = {},
    source_path = nil,
  }
  states[buf] = state
  ensure_watchfiles_handler()

  vim.api.nvim_create_autocmd("BufWritePost", {
    group = state.group,
    buffer = buf,
    callback = function()
      M.refresh(buf)
    end,
  })
  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    group = state.group,
    buffer = buf,
    once = true,
    callback = function()
      M.detach(buf)
    end,
  })

  M.refresh(buf)
end

---@param buf integer
M.detach = function(buf)
  local state = states[buf]
  if not state then
    return
  end
  states[buf] = nil
  watch_refresh_pending[buf] = nil
  if vim.api.nvim_buf_is_valid(buf) then
    vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)
  end
  pcall(vim.api.nvim_del_augroup_by_id, state.group)
  prune_cache()

  if not next(states) and unregister_watchfiles then
    unregister_watchfiles()
    unregister_watchfiles = nil
    note_cache = {}
  end
end

function M.detach_all()
  for _, buf in ipairs(vim.tbl_keys(states)) do
    M.detach(buf)
  end
end

---Compatibility alias: starting now attaches a live embed renderer.
M.start = M.attach

return M
