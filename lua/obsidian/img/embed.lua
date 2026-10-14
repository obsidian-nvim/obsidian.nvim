local M = {}
local states = {}
local max_image_width = 80 -- cells
local max_image_height = 30 -- cells

local function parse_size(label)
  if type(label) ~= "string" then
    return nil, nil
  end
  local width_str, height_str = label:match "^(%d+)[xX](%d+)$"
  if width_str then
    local width, height = tonumber(width_str), tonumber(height_str)
    if width > 0 and height > 0 then
      return width, height
    end
    return nil, nil
  end
  local width = tonumber(label:match "^(%d+)$")
  return width and width > 0 and width or nil, nil
end

local function close_state(bufnr)
  local state = states[bufnr]
  if not state then
    return
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  for _, entry in ipairs(state.entries) do
    entry.owner:close()
  end
  state.entries = {}
end

-- Buffer placements start at the text column, not the terminal's left edge.
-- Account for the number/sign/fold gutter when fitting the image to a split.
local function text_width(bufnr)
  local width
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
    if vim.api.nvim_win_get_buf(win) == bufnr and vim.api.nvim_win_get_config(win).relative == "" then
      local info = vim.fn.getwininfo(win)[1]
      if info then
        width = math.min(width or math.huge, info.width - info.textoff)
      end
    end
  end
  return width
end

local function find_embeds(lines)
  local refs = require "obsidian.parse.refs"
  local Document = require "obsidian.parse.document"
  local document = Document.parse(lines)
  local attachment = require "obsidian.attachment"
  local embeds = {}
  for row, line in ipairs(lines) do
    ---@cast row integer
    for _, ref in ipairs(refs.extract(line, { row = row - 1, lexical = true })) do
      if
        ref.embed
        and ref.kind ~= "footnote"
        and attachment.is_attachment_path(ref.target)
        and not document:intersects(ref.range, Document.INLINE_EXCLUSIONS)
      then
        embeds[#embeds + 1] = { ref = ref, row = row }
        break
      end
    end
  end
  return embeds
end

local function image_placement(bufnr, row, available_width, cell_width, cell_height, width_px, height_px)
  local max_width = math.min(max_image_width, available_width)
  local max_height = max_image_height
  if width_px then
    max_width = math.min(max_width, math.max(1, math.ceil(width_px / cell_width)))
  end
  if height_px then
    max_height = math.min(max_height, math.max(1, math.ceil(height_px / cell_height)))
  end
  return {
    relative = "buffer",
    buf = bufnr,
    row = row,
    col = 1,
    pad = 0,
    max_width = max_width,
    max_height = max_height,
  }
end

local function render(bufnr)
  local state = states[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  local available_width = text_width(bufnr)
  if not available_width or available_width < 1 then
    return
  end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local embeds = find_embeds(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  local attachment = require "obsidian.attachment"
  local img = require "obsidian.img"
  local cell = img.cell_pixels()
  -- Match occurrences independently of their row: edits above an embed move
  -- its anchor, but do not change the image bytes or invalidate other embeds.
  local previous = {}
  for _, entry in ipairs(state.entries) do
    previous[entry.signature] = previous[entry.signature] or {}
    table.insert(previous[entry.signature], entry)
  end
  local entries = {}
  for _, embed in ipairs(embeds) do
    local ref, row = embed.ref, embed.row
    local signature = filename .. "\0" .. ref.target
    local matches = previous[signature]
    local entry = matches and table.remove(matches, 1)
    local fresh = not entry
    if fresh then
      entry = { signature = signature, owner = img.owner { kind = "inline-embed", buf = bufnr }, request = 0 }
    end
    entries[#entries + 1] = entry
    local width_px, height_px
    if ref.kind == "wiki" then
      width_px, height_px = parse_size(ref.label)
    end
    local next_placement = image_placement(bufnr, row, available_width, cell.width, cell.height, width_px, height_px)
    if not vim.deep_equal(next_placement, entry.placement) then
      -- Also update pending loads, so they use the latest row and pane size.
      local ok = entry.owner:update(next_placement)
      if ok or not entry.owner.image_id then
        entry.placement = next_placement
      end
    end
    if fresh or state.force_render then
      entry.request = entry.request + 1
      local request = entry.request
      attachment._resolve_async(ref.target, { bufnr = bufnr, filename = filename }, function(path)
        if entry.owner.closed or entry.request ~= request or not vim.api.nvim_buf_is_valid(bufnr) or not path then
          return
        end
        entry.owner:show { source = path, placement = entry.placement }
      end)
    end
    -- One image per line keeps virtual lines deterministic and non-overlapping.
  end
  for _, matches in pairs(previous) do
    for _, entry in ipairs(matches) do
      entry.owner:close()
    end
  end
  state.entries = entries
  state.force_render = nil
end

local function schedule_render(bufnr)
  local state = states[bufnr]
  if not state then
    return
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end
  state.timer = vim.defer_fn(function()
    state.timer = nil
    render(bufnr)
  end, 100)
end

---Refresh inline placements after changing a note or its attachments.
---@param bufnr? integer
function M.refresh(bufnr)
  bufnr = bufnr or vim.api.nvim_get_current_buf()
  local state = states[bufnr]
  if not state then
    return
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  state.force_render = true
  render(bufnr)
end

function M.setup(workspace, img_opts)
  for bufnr in pairs(states) do
    close_state(bufnr)
    states[bufnr] = nil
  end
  local group = vim.api.nvim_create_augroup("ObsidianImgEmbed", { clear = true })
  if not img_opts.enabled then
    return
  end
  if not require("obsidian.img").capabilities().buffer then
    require("obsidian.log").warn_once "Inline images require vim.ui.img buffer placement support (neovim/neovim#39496); run :checkhealth obsidian"
    return
  end

  local pattern = tostring(workspace.root) .. "/**.md"
  vim.api.nvim_create_autocmd({ "BufEnter", "BufWinEnter", "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    pattern = pattern,
    callback = function(ev)
      local bufnr = ev.buf
      if not states[bufnr] then
        states[bufnr] = { entries = {} }
      end
      schedule_render(bufnr)
    end,
  })
  local function refresh_layout()
    for bufnr in pairs(states) do
      schedule_render(bufnr)
    end
  end
  vim.api.nvim_create_autocmd({ "WinResized", "WinClosed", "VimResized", "TabEnter" }, {
    group = group,
    callback = refresh_layout,
  })
  vim.api.nvim_create_autocmd("OptionSet", {
    group = group,
    pattern = { "number", "relativenumber", "numberwidth", "signcolumn", "foldcolumn" },
    callback = refresh_layout,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    pattern = pattern,
    callback = function(ev)
      close_state(ev.buf)
      states[ev.buf] = nil
    end,
  })
end

return M
