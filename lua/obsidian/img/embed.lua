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
  state.generation = state.generation + 1
  if state.timer then
    state.timer:stop()
    state.timer:close()
    state.timer = nil
  end
  for _, owner in ipairs(state.owners) do
    owner:close()
  end
  state.owners = {}
end

-- Buffer placements start at the text column, not the terminal's left edge.
-- Account for the number/sign/fold gutter when fitting the image to a split.
local function text_width(bufnr)
  local width
  for _, win in ipairs(vim.api.nvim_list_wins()) do
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

local function embed_signature(ref)
  return table.concat({ ref.kind, ref.raw, ref.target, ref.label or "" }, "\0")
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

local function render(bufnr, opts)
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
  local cell_width, cell_height = img.cell_pixels()
  local signature = {}
  for _, embed in ipairs(embeds) do
    local ref = embed.ref
    signature[#signature + 1] = embed_signature(ref)
  end
  if not state.force_render and vim.deep_equal(signature, state.signature) then
    return
  end
  state.force_render = nil
  state.signature = signature
  state.generation = state.generation + 1
  local generation = state.generation
  for _, owner in ipairs(state.owners) do
    owner:close()
  end
  state.owners = {}
  state.resized = state.resized or {}

  for i, embed in ipairs(embeds) do
    local ref, row = embed.ref, embed.row
    local width_px, height_px
    if ref.kind == "wiki" then
      width_px, height_px = parse_size(ref.label)
      local resized = state.resized[i]
      if resized and resized.signature == signature[i] and not ref.label then
        width_px, height_px = resized.width, resized.height
      else
        state.resized[i] = nil
      end
    end
    local owner = img.owner {
      kind = "inline-embed",
      buf = bufnr,
      max_bytes = opts.max_file_size,
    }
    state.owners[#state.owners + 1] = owner
    attachment._resolve_async(ref.target, { bufnr = bufnr, filename = filename }, function(path)
      if state.generation ~= generation or not vim.api.nvim_buf_is_valid(bufnr) or not path then
        return
      end
      owner:show {
        source = { path = path },
        placement = image_placement(bufnr, row, available_width, cell_width, cell_height, width_px, height_px),
        require_buffer_lines = true,
      }
    end)
    -- A buffer-relative image inserts virtual lines below its anchor. One per line
    -- gives deterministic ordering and avoids overlapping images on a shared row.
  end
end

---Resize a rendered wiki embed under the cursor. Explicit size labels are
---edited; an implicit size is changed only in the current buffer's image state.
---@param delta integer Direction of the change.
---@return boolean
function M.resize_under_cursor(delta)
  local bufnr = vim.api.nvim_get_current_buf()
  local state = states[bufnr]
  if not state or delta == 0 or not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly then
    return false
  end
  local cursor = vim.api.nvim_win_get_cursor(0)
  local row, col = cursor[1] - 1, cursor[2]
  local embeds = find_embeds(vim.api.nvim_buf_get_lines(bufnr, 0, -1, false))
  for i, embed in ipairs(embeds) do
    local ref = embed.ref
    if ref.kind == "wiki" and ref.range.start_row == row and ref.range.start_col <= col and col < ref.range.end_col then
      local owner = state.owners[i]
      if not owner or not owner.image_id or state.signature[i] ~= embed_signature(ref) then
        return false
      end
      local width, height = parse_size(ref.label)
      if ref.label and not width then
        return false
      end
      local dimensions = owner.dimensions
      local available_width = text_width(bufnr)
      if not dimensions or not available_width then
        return false
      end
      local img = require "obsidian.img"
      local cell_width, cell_height = img.cell_pixels()
      local max_width = math.min(max_image_width, available_width)
      if not width then
        local resized = state.resized and state.resized[i]
        if resized and resized.signature == state.signature[i] then
          width, height = resized.width, resized.height
        else
          local fitted_width = img.fit(dimensions.width, dimensions.height, max_width, max_image_height)
          width = math.floor(fitted_width * cell_width + 0.5)
        end
      end
      local explicit_height = height ~= nil
      height = height or math.max(1, math.floor(width * dimensions.height / dimensions.width + 0.5))
      local limit = math.floor(math.min(max_width * cell_width, max_image_height * cell_height * width / height))
      local current_placement = owner.placement
      if not current_placement then
        return false
      end
      local _, shown_height =
        img.fit(dimensions.width, dimensions.height, current_placement.max_width, current_placement.max_height)
      -- The pixel-to-cell conversion is quantized. Find the nearest proportional
      -- size that changes the *rendered* height by a cell, never width alone.
      local function rendered_height(candidate_width)
        local candidate_height = math.max(1, math.floor(height * candidate_width / width + 0.5))
        local placement =
          image_placement(bufnr, embed.row, available_width, cell_width, cell_height, candidate_width, candidate_height)
        local _, rows = img.fit(dimensions.width, dimensions.height, placement.max_width, placement.max_height)
        return rows
      end
      ---@type number, number
      local low, high = delta > 0 and width + 1 or 1, delta > 0 and limit or math.min(width - 1, limit)
      local next_width
      while low <= high do
        local mid = math.floor((low + high) / 2)
        local rows = rendered_height(mid)
        if delta > 0 then
          if rows > shown_height then
            next_width = mid
            high = mid - 1
          else
            low = mid + 1
          end
        elseif rows < shown_height then
          next_width = mid
          low = mid + 1
        else
          high = mid - 1
        end
      end
      if not next_width then
        return false
      end
      local next_height = math.max(1, math.floor(height * next_width / width + 0.5))
      if not ref.label then
        local ok = owner:update(
          image_placement(bufnr, embed.row, available_width, cell_width, cell_height, next_width, next_height)
        )
        if not ok then
          M.refresh(bufnr)
          return false
        end
        state.resized = state.resized or {}
        state.resized[i] = { signature = state.signature[i], width = next_width, height = next_height }
        return true
      end
      local next_label = explicit_height and next_width .. "x" .. next_height or tostring(next_width)
      local prefix = ref.raw:sub(1, #ref.raw - 2 - (ref.label and #ref.label + 1 or 0))
      vim.api.nvim_buf_set_text(
        bufnr,
        row,
        ref.range.start_col,
        row,
        ref.range.end_col,
        { prefix .. "|" .. next_label .. "]]" }
      )
      M.refresh(bufnr)
      return true
    end
  end
  return false
end

local function schedule_render(bufnr, opts, force)
  local state = states[bufnr]
  if not state then
    return
  end
  if state.timer then
    state.timer:stop()
    state.timer:close()
  end
  state.force_render = state.force_render or force
  state.timer = vim.defer_fn(function()
    state.timer = nil
    render(bufnr, opts)
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
  render(bufnr, state.opts)
end

function M.setup(workspace, img_opts)
  for bufnr in pairs(states) do
    close_state(bufnr)
    states[bufnr] = nil
  end
  local group = vim.api.nvim_create_augroup("ObsidianImgEmbed", { clear = true })
  local opts = img_opts.embeds or {}
  if not img_opts.enabled or not opts.enabled then
    return
  end

  local pattern = tostring(workspace.root) .. "/**.md"
  vim.api.nvim_create_autocmd({ "BufEnter", "TextChanged", "TextChangedI", "TextChangedP" }, {
    group = group,
    pattern = pattern,
    callback = function(ev)
      local bufnr = ev.buf
      if not states[bufnr] then
        states[bufnr] = { owners = {}, generation = 0, opts = img_opts }
      end
      schedule_render(bufnr, img_opts)
    end,
  })
  vim.api.nvim_create_autocmd("WinResized", {
    group = group,
    callback = function()
      for bufnr in pairs(states) do
        schedule_render(bufnr, img_opts, true)
      end
    end,
  })
  -- The ui2 :messages pager can clear Kitty images without changing the note.
  -- Returning to its window needs a retransmit even when embed text is unchanged.
  vim.api.nvim_create_autocmd("WinEnter", {
    group = group,
    callback = function()
      local bufnr = vim.api.nvim_get_current_buf()
      if states[bufnr] then
        schedule_render(bufnr, img_opts, true)
      end
    end,
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
