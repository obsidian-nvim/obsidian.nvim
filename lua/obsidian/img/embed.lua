local M = {}
local states = {}

local function parse_size(label)
  if type(label) ~= "string" then
    return nil, nil
  end
  local width, height = label:match "^(%d+)[xX](%d+)$"
  if width then
    return tonumber(width), tonumber(height)
  end
  width = label:match "^(%d+)$"
  return tonumber(width), nil
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

local function render(bufnr, opts)
  local state = states[bufnr]
  if not state or not vim.api.nvim_buf_is_valid(bufnr) then
    return
  end
  state.generation = state.generation + 1
  local generation = state.generation
  for _, owner in ipairs(state.owners) do
    owner:close()
  end
  state.owners = {}

  local available_width = text_width(bufnr)
  if not available_width or available_width < 1 then
    return
  end
  local filename = vim.api.nvim_buf_get_name(bufnr)
  local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  local refs = require "obsidian.parse.refs"
  local Document = require "obsidian.parse.document"
  local document = Document.parse(lines)
  local attachment = require "obsidian.attachment"
  for row, line in ipairs(lines) do
    for _, ref in ipairs(refs.extract(line, { row = row - 1, lexical = true })) do
      if
        ref.embed
        and ref.kind ~= "footnote"
        and attachment.is_attachment_path(ref.target)
        and not document:intersects(ref.range, Document.INLINE_EXCLUSIONS)
      then
        local width_px, height_px
        if ref.kind == "wiki" then
          width_px, height_px = parse_size(ref.label)
        end
        local owner = require("obsidian.img").owner {
          kind = "inline-embed",
          buf = bufnr,
          max_bytes = opts.max_file_size,
        }
        state.owners[#state.owners + 1] = owner
        attachment._resolve_async(ref.target, { bufnr = bufnr, filename = filename }, function(path)
          if state.generation ~= generation or not vim.api.nvim_buf_is_valid(bufnr) or not path then
            return
          end
          local max_width = math.min(opts.embeds.max_width, available_width)
          local max_height = opts.embeds.max_height
          if width_px then
            max_width = math.min(max_width, math.max(1, math.ceil(width_px / 9)))
          end
          if height_px then
            max_height = math.min(max_height, math.max(1, math.ceil(height_px / 18)))
          end
          ---@cast max_width integer
          ---@cast max_height integer
          owner:show {
            source = { path = path },
            placement = {
              relative = "buffer",
              buf = bufnr,
              row = row,
              col = 1,
              pad = 0,
              max_width = max_width,
              max_height = max_height,
            },
            require_buffer_lines = true,
          }
        end)
        -- A buffer-relative image inserts virtual lines below its anchor. One per line
        -- gives deterministic ordering and avoids overlapping images on a shared row.
        break
      end
    end
  end
end

local function schedule_render(bufnr, opts)
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
        schedule_render(bufnr, img_opts)
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
