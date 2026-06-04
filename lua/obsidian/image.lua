local util = require "obsidian.util"
local attachment = require "obsidian.attachment"

local M = {}

local ns = vim.api.nvim_create_namespace "obsidian.image"

---@alias obsidian.image.Placement "inline"|"hover"|"fixed"

---@class obsidian.image.Opts
---@field placement? obsidian.image.Placement
---@field width? integer
---@field height? integer
---@field zindex? integer
---@field pad? integer
---@field conceal? boolean|string
---@field formats? string[]
---@field visible_only? boolean
---@field margin? integer
---@field debounce? integer
---@field enabled? boolean

---@class obsidian.image.Match
---@field src string
---@field path string
---@field row integer 0-indexed
---@field col integer 0-indexed
---@field end_col integer 0-indexed, exclusive
---@field key string
---@field win? integer

---@class obsidian.image.Rendered
---@field id integer
---@field buf integer
---@field opts table
---@field anchor? integer
---@field spacer? integer

---@class obsidian.image.State
---@field buf integer
---@field group integer
---@field opts obsidian.image.Opts
---@field rendered table<string, obsidian.image.Rendered>
---@field timer uv.uv_timer_t?
---@field force? boolean

---@type table<integer, obsidian.image.State>
local states = {}

local defaults = {
  placement = "inline",
  zindex = 50,
  visible_only = true,
  margin = 10,
  debounce = 50,
  formats = { "png" },
}

---@param opts obsidian.image.Opts|?
---@return obsidian.image.Opts
local function normalize_opts(opts)
  return vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
end

---@param path string
---@param formats string[]
---@return boolean
local function supported_format(path, formats)
  local ext = path:match "%.([^./\\]+)$"
  return ext ~= nil and vim.list_contains(formats, ext:lower())
end

---@param path string
---@return boolean
local function exists(path)
  return path ~= "" and vim.uv.fs_stat(path) ~= nil
end

---@return boolean supported
function M.supported()
  if type(vim.ui) ~= "table" or type(vim.ui.img) ~= "table" or type(vim.ui.img.set) ~= "function" then
    return false
  end

  if type(vim.ui.img._supported) == "function" then
    local ok, supported = pcall(vim.ui.img._supported)
    return ok and supported == true
  end

  return true
end

---@param path string
---@return string data
local function read_file(path)
  if vim.fn.exists "*readblob" == 1 then
    local ok, data = pcall(vim.fn.readblob, path)
    if ok then
      return data
    end
  end

  local fd = assert(io.open(path, "rb"))
  local data = assert(fd:read "*a")
  fd:close()
  return data
end

---@param target string
---@return string
local function clean_target(target)
  target = vim.trim(target)
  target = target:gsub("^<(.+)>$", "%1")

  -- Drop markdown titles from `![alt](foo.png "title")`.
  local first = target:match "^(%S+)%s+['\"].-['\"]$"
  if first then
    target = first
  end

  -- Obsidian wiki embeds can be `![[image.png|300x200]]`.
  target = target:match "^([^|]+)" or target

  -- Local images don't need query/fragment components for filesystem lookup.
  target = target:gsub("#.*$", ""):gsub("%?.*$", "")
  target = target:gsub("\\ ", " ")
  return vim.uri_decode(target)
end

---@param path string
---@return boolean
local function is_absolute(path)
  return vim.startswith(path, "/") or path:match "^%a:[/\\]" ~= nil
end

---@param src string
---@param bufnr integer
---@return string?
local function resolve_path(src, bufnr)
  src = clean_target(src)
  if src == "" then
    return nil
  end

  local is_uri, scheme = util.is_uri(src)
  if is_uri then
    if scheme == "file" then
      return vim.uri_to_fname(src)
    end
    return nil
  end

  if is_absolute(src) and exists(src) then
    return src
  end

  local buf_name = vim.api.nvim_buf_get_name(bufnr)
  local buf_dir = buf_name ~= "" and vim.fs.dirname(buf_name) or vim.fn.getcwd()
  local candidates = {
    vim.fs.normalize(buf_dir .. "/" .. src),
  }

  if Obsidian and Obsidian.dir then
    candidates[#candidates + 1] = vim.fs.normalize(tostring(Obsidian.dir) .. "/" .. src)
  end

  if Obsidian and Obsidian.opts and Obsidian.opts.attachments then
    candidates[#candidates + 1] = attachment.resolve_attachment_path(src, bufnr)
  end

  for _, candidate in ipairs(candidates) do
    if exists(candidate) then
      return candidate
    end
  end
end

---@param line string
---@param row integer
---@param bufnr integer
---@param opts obsidian.image.Opts
---@param win integer|?
---@return obsidian.image.Match[]
local function find_line_images(line, row, bufnr, opts, win)
  ---@type obsidian.image.Match[]
  local ret = {}

  local function add(start_col, end_col, src)
    local path = resolve_path(src, bufnr)
    if not path or not supported_format(path, opts.formats or defaults.formats) then
      return
    end
    ret[#ret + 1] = {
      src = src,
      path = path,
      row = row,
      col = start_col,
      end_col = end_col,
      key = table.concat({ row, start_col, end_col, path }, ":"),
      win = win,
    }
  end

  for start_col, body, end_pos in line:gmatch "()!%[%[([^%]]+)%]%]()" do
    add(start_col - 1, end_pos - 1, body)
  end

  for start_col, target, end_pos in line:gmatch "()!%[[^%]]*%]%(([^%)]+)%)()" do
    add(start_col - 1, end_pos - 1, target)
  end

  return ret
end

---@param bufnr integer
---@return integer[]
local function visible_wins(bufnr)
  local wins = {}
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
      wins[#wins + 1] = win
    end
  end
  return wins
end

---@param bufnr integer
---@param opts obsidian.image.Opts
---@param win integer|?
---@return integer start_row 0-indexed, inclusive
---@return integer end_row 0-indexed, exclusive
local function visible_range(bufnr, opts, win)
  if not opts.visible_only then
    return 0, vim.api.nvim_buf_line_count(bufnr)
  end

  if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == bufnr then
    local start_row, end_row
    vim.api.nvim_win_call(win, function()
      start_row = vim.fn.line "w0"
      end_row = vim.fn.line "w$"
    end)
    local margin = opts.margin or 0
    return math.max(start_row - 1 - margin, 0), math.min(end_row + margin, vim.api.nvim_buf_line_count(bufnr))
  end

  return 0, 0
end

---@param state obsidian.image.State
---@return obsidian.image.Match[]
local function find_images(state)
  local wins = visible_wins(state.buf)
  if #wins == 0 then
    return {}
  end

  ---@type obsidian.image.Match[]
  local matches = {}
  local seen = {}
  for _, win in ipairs(wins) do
    local start_row, end_row = visible_range(state.buf, state.opts, win)
    local lines = vim.api.nvim_buf_get_lines(state.buf, start_row, end_row, false)
    for i, line in ipairs(lines) do
      for _, match in ipairs(find_line_images(line, start_row + i - 1, state.buf, state.opts, win)) do
        if not seen[match.key] then
          seen[match.key] = true
          matches[#matches + 1] = match
        end
      end
    end
  end
  return matches
end

local renderers = {}
M.renderers = renderers

---@param match obsidian.image.Match
---@param state obsidian.image.State
---@return table? opts
function renderers.inline(match, state)
  return {
    relative = "buffer",
    buf = state.buf,
    -- Buffer mode uses buffer coordinates. The virt_lines are attached to this
    -- row and rendered below it, after sign/number columns, so don't add any
    -- screen-space offset here.
    row = match.row + 1,
    col = match.col + 1,
    pad = match.col,
    width = state.opts.width,
    height = state.opts.height,
    zindex = state.opts.zindex,
  }
end

---@param _match obsidian.image.Match
---@param _state obsidian.image.State
function renderers.hover(_match, _state)
  error "obsidian.image: hover placement is not implemented yet"
end

---@param _match obsidian.image.Match
---@param _state obsidian.image.State
function renderers.fixed(_match, _state)
  error "obsidian.image: fixed placement is not implemented yet"
end

---@param rendered obsidian.image.Rendered
local function del_rendered(rendered)
  if M.supported() and type(vim.ui.img.del) == "function" then
    pcall(vim.ui.img.del, rendered.id)
  end
  if rendered.anchor then
    pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.anchor)
  end
  if rendered.spacer then
    pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.spacer)
  end
end

---@param rendered obsidian.image.Rendered
---@param state obsidian.image.State
---@param match obsidian.image.Match
local function update_spacer(rendered, state, match)
  if (state.opts.placement or "inline") ~= "inline" then
    return
  end

  if rendered.opts and rendered.opts.relative == "buffer" then
    if rendered.spacer then
      pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.spacer)
      rendered.spacer = nil
    end
    return
  end

  local height = state.opts.height
  if not height and type(vim.ui.img.get) == "function" then
    local ok, img_opts = pcall(vim.ui.img.get, rendered.id)
    if ok and img_opts then
      height = img_opts.height
    end
  end

  if type(height) ~= "number" or height <= 0 then
    return
  end

  if rendered.spacer then
    pcall(vim.api.nvim_buf_del_extmark, rendered.buf, ns, rendered.spacer)
  end

  local virt_lines = {}
  for i = 1, height do
    virt_lines[i] = { { " ", "Normal" } }
  end
  rendered.spacer = vim.api.nvim_buf_set_extmark(state.buf, ns, match.row, 0, {
    virt_lines = virt_lines,
    virt_lines_above = false,
    invalidate = true,
    undo_restore = false,
  })
end

---@param state obsidian.image.State
---@param match obsidian.image.Match
---@param rendered obsidian.image.Rendered?
---@return obsidian.image.Rendered?
local function render_match(state, match, rendered)
  local renderer = renderers[state.opts.placement or "inline"]
  if not renderer then
    error("obsidian.image: unknown placement " .. tostring(state.opts.placement))
  end

  local img_opts = renderer(match, state)
  if not img_opts then
    return nil
  end

  if rendered then
    local ok = pcall(vim.ui.img.set, rendered.id, img_opts)
    if not ok then
      return nil
    end
    rendered.opts = img_opts
    update_spacer(rendered, state, match)
    return rendered
  end

  local ok, data = pcall(read_file, match.path)
  if not ok then
    return nil
  end

  local set_ok, id = pcall(vim.ui.img.set, data, img_opts)
  if not set_ok then
    return nil
  end
  rendered = { id = id, buf = state.buf, opts = img_opts }

  if state.opts.conceal then
    local conceal = type(state.opts.conceal) == "string" and state.opts.conceal or ""
    rendered.anchor = vim.api.nvim_buf_set_extmark(state.buf, ns, match.row, match.col, {
      end_row = match.row,
      end_col = match.end_col,
      conceal = conceal,
      invalidate = true,
      undo_restore = false,
    })
  end

  update_spacer(rendered, state, match)

  return rendered
end

---@param bufnr integer
---@param force boolean|?
function M.refresh(bufnr, force)
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) or not M.supported() then
    return
  end

  local next_rendered = {} ---@type table<string, obsidian.image.Rendered>
  for _, match in ipairs(find_images(state)) do
    local previous = state.rendered[match.key]
    if force and previous then
      del_rendered(previous)
      previous = nil
    end
    local rendered = render_match(state, match, previous)
    if rendered then
      next_rendered[match.key] = rendered
    end
  end

  for key, rendered in pairs(state.rendered) do
    if not next_rendered[key] then
      del_rendered(rendered)
    end
  end

  state.rendered = next_rendered
end

---@param state obsidian.image.State
---@param force boolean|?
local function schedule_refresh(state, force)
  state.force = state.force or force
  if state.timer then
    state.timer:stop()
  else
    state.timer = assert(vim.uv.new_timer())
  end
  state.timer:start(
    state.opts.debounce or 0,
    0,
    vim.schedule_wrap(function()
      local refresh_force = state.force
      state.force = false
      M.refresh(state.buf, refresh_force)
    end)
  )
end

---@param bufnr integer|?
---@param opts obsidian.image.Opts|?
function M.attach(bufnr, opts)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr

  if not M.supported() then
    return
  end

  if states[bufnr] then
    M.detach(bufnr)
  end

  local state = {
    buf = bufnr,
    group = vim.api.nvim_create_augroup("obsidian.image." .. bufnr, { clear = true }),
    opts = normalize_opts(opts),
    rendered = {},
  }
  states[bufnr] = state

  vim.api.nvim_create_autocmd({ "BufWinEnter", "TextChanged", "TextChangedI", "BufWritePost" }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      schedule_refresh(state)
    end,
  })

  vim.api.nvim_create_autocmd("WinScrolled", {
    group = state.group,
    callback = function()
      schedule_refresh(state)
    end,
  })

  vim.api.nvim_create_autocmd({ "WinResized", "VimResized" }, {
    group = state.group,
    callback = function()
      schedule_refresh(state, true)
    end,
  })

  vim.api.nvim_create_autocmd({ "BufWipeout", "BufDelete" }, {
    group = state.group,
    buffer = bufnr,
    callback = function()
      M.detach(bufnr)
    end,
  })

  schedule_refresh(state)
end

---@param bufnr integer|?
---@return boolean
function M.is_attached(bufnr)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  return states[bufnr] ~= nil
end

---@param bufnr integer|?
function M.detach(bufnr)
  bufnr = bufnr or 0
  bufnr = bufnr == 0 and vim.api.nvim_get_current_buf() or bufnr
  local state = states[bufnr]
  if not state then
    return
  end

  if state.timer then
    state.timer:stop()
    state.timer:close()
  end

  for _, rendered in pairs(state.rendered) do
    del_rendered(rendered)
  end
  states[bufnr] = nil
  pcall(vim.api.nvim_del_augroup_by_id, state.group)
end

function M.detach_all()
  local bufs = vim.tbl_keys(states)
  for _, bufnr in ipairs(bufs) do
    M.detach(bufnr)
  end
end

-- Snacks-shaped entrypoints, so callers currently doing
-- `require("snacks.image").doc.attach(buf)` can switch to this module with the
-- smallest possible diff.
M.doc = {
  attach = M.attach,
  detach = M.detach,
}

M.inline = {
  attach = M.attach,
  detach = M.detach,
  refresh = M.refresh,
}

vim.api.nvim_create_autocmd("VimLeavePre", {
  callback = M.detach_all,
})

return M
