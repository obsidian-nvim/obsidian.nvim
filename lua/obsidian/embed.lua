local search = require "obsidian.search"
local ts = require "obsidian.ts"
local watchfiles = require "obsidian.lsp.watchfiles"

local M = {}

local ns_id = vim.api.nvim_create_namespace "obsidian-nvim-embeds"
local LEFT_SEP = "▏"
local MAX_PREVIEW_LINES = 10
local MAX_NOTE_LINES = 2147483647

---@class obsidian.embed.Context
---@field path string|nil
---@field note obsidian.Note
---@field fragment string|nil
---@field range obsidian.Range|nil

---@class obsidian.embed.State
---@field buf integer
---@field group integer
---@field dependencies table<string, boolean>
---@field source_path string|nil
---@field previews table<string, obsidian.embed.Preview>

---@class obsidian.embed.Match
---@field col integer 0-indexed
---@field end_col integer 0-indexed, exclusive
---@field target string

---@class obsidian.embed.Preview
---@field offset integer
---@field total integer
---@field limit integer

---@class obsidian.embed.CacheEntry
---@field path string
---@field lines table[]

---@type table<integer, obsidian.embed.State>
local states = {}

---@type table<string, obsidian.embed.CacheEntry>
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

---@param context obsidian.embed.Context
---@return string[]
local function note_lines(context)
  local lines = {}
  if context.range then
    for row = context.range.start_row, context.range.end_row - 1 do
      lines[#lines + 1] = context.note.contents[row + 1]
    end
  else
    local start_line = context.note.frontmatter_end_line and context.note.frontmatter_end_line + 1 or 1
    for line_num = start_line, #context.note.contents do
      lines[#lines + 1] = context.note.contents[line_num]
    end
  end
  return lines
end

---@param context obsidian.embed.Context
---@return table[]
local function render_note(context)
  local path = context.path and normalize(context.path)
  local cache_key = path and path .. "\0" .. (context.fragment or "")
  local cached = cache_key and note_cache[cache_key]
  if cached then
    return cached.lines
  end

  local virt_lines = ts.to_virt_lines(note_lines(context))
  for _, line in ipairs(virt_lines) do
    with_separator(line)
  end
  if cache_key and path then
    note_cache[cache_key] = { path = path, lines = virt_lines }
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
  for col, body, end_pos in line:gmatch "()!%[%[([^%]]+)%]%]()" do
    matches[#matches + 1] = {
      col = col - 1,
      end_col = end_pos - 1,
      target = clean_wiki_target(body),
    }
  end
  for col, body, end_pos in line:gmatch "()!%[[^%]]*%]%(([^%)]+)%)()" do
    matches[#matches + 1] = {
      col = col - 1,
      end_col = end_pos - 1,
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
---@return string|nil
local function target_parts(target)
  local path, fragment = target:match "^(.-)#(.*)$"
  path = (path or target):gsub("%?.*$", "")
  if fragment then
    fragment = fragment:gsub("%?.*$", "")
  end
  return path, fragment ~= "" and fragment or nil
end

---@param row integer 0-indexed
---@param match obsidian.embed.Match
---@return string
local function preview_key(row, match)
  return table.concat({ row, match.col, match.end_col, match.target }, ":")
end

---@param lines table[]
---@param offset integer
---@param limit integer
---@return table[]
local function slice(lines, offset, limit)
  local result = {}
  for i = offset + 1, math.min(#lines, offset + limit) do
    result[#result + 1] = lines[i]
  end
  return result
end

---@param match obsidian.embed.Match
---@param buf integer
---@return obsidian.embed.Context|nil
local function resolve_context(match, buf)
  local target, fragment = target_parts(match.target)
  if not is_markdown(target) then
    return nil
  end

  local note_opts = { max_lines = MAX_NOTE_LINES }
  if fragment then
    if vim.startswith(fragment, "^") then
      note_opts.collect_blocks = true
    else
      note_opts.collect_anchor_links = true
    end
  end

  ---@type obsidian.Note|nil
  local note
  if target == "" then
    local ok, result = pcall(require("obsidian.note").from_buffer, buf, note_opts)
    if not ok then
      return nil
    end
    note = result
  else
    local ok, notes = pcall(search.resolve_note, target, { notes = note_opts })
    if not ok or not notes or not notes[1] then
      return nil
    end
    note = notes[1]
  end
  ---@cast note -nil

  ---@type obsidian.Range|nil
  local range
  if fragment then
    if vim.startswith(fragment, "^") then
      local block = note:resolve_block(fragment)
      range = block and block.section and block.section.range or nil
    else
      local anchor = note:resolve_anchor_link(fragment)
      range = anchor and anchor.section and anchor.section.range or nil
    end
    if not range then
      return nil
    end
  end

  return {
    path = note.path and normalize(tostring(note.path)) or nil,
    note = note,
    fragment = fragment,
    range = range,
  }
end

---@param path string|nil
local function invalidate(path)
  if not path then
    return
  end
  path = normalize(path)
  for key, cached in pairs(note_cache) do
    if cached.path == path then
      note_cache[key] = nil
    end
  end
end

local function prune_cache()
  local active = {}
  for _, state in pairs(states) do
    for path in pairs(state.dependencies) do
      active[path] = true
    end
  end
  for key, cached in pairs(note_cache) do
    if not active[cached.path] then
      note_cache[key] = nil
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
  local previous_previews = state.previews
  state.previews = {}
  vim.api.nvim_buf_clear_namespace(buf, ns_id, 0, -1)

  local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
  for line_num, line in ipairs(lines) do
    local rendered = {}
    for _, match in ipairs(find_embeds(line)) do
      local context = resolve_context(match, buf)
      if context then
        if context.path then
          state.dependencies[normalize(context.path)] = true
        end
        local ok, virt_lines = pcall(render_note, context)
        if ok and virt_lines then
          local key = preview_key(line_num - 1, match)
          local previous = previous_previews[key]
          local limit = context.range and #virt_lines or MAX_PREVIEW_LINES
          local max_offset = math.max(0, #virt_lines - limit)
          local offset = math.min(previous and previous.offset or 0, max_offset)
          state.previews[key] = { offset = offset, total = #virt_lines, limit = limit }
          vim.list_extend(rendered, slice(virt_lines, offset, limit))
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

---Scroll the note embed under the cursor by virtual lines.
---Positive values move the preview up; negative values move it down.
---@param delta integer
---@return boolean|nil changed `nil` when the cursor is not on a rendered note embed.
M.scroll_under_cursor = function(delta)
  local buf = vim.api.nvim_get_current_buf()
  local state = states[buf]
  if not state or delta == 0 then
    return nil
  end

  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local line = vim.api.nvim_buf_get_lines(buf, row, row + 1, false)[1]
  if not line then
    return nil
  end

  for _, match in ipairs(find_embeds(line)) do
    if match.col <= col and col < match.end_col then
      local key = preview_key(row, match)
      local preview = state.previews[key]
      if not preview then
        M.refresh(buf)
        state = states[buf]
        preview = state and state.previews[key] or nil
      end
      if not preview then
        return nil
      end

      local next_offset = math.max(0, math.min(preview.total - preview.limit, preview.offset + delta))
      if next_offset == preview.offset then
        return false
      end

      preview.offset = next_offset
      M.refresh(buf)
      return true
    end
  end
  return nil
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
    previews = {},
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
