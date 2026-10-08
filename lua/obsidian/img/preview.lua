-- Image previews belong to named path-preview buffers and their display
-- windows, not to a particular picker implementation. Each window owns only
-- its own image id.
local filetypes = require "obsidian.filetypes"

local M = {}

---@class obsidian.img.PreviewState
---@field owner obsidian.img.Owner
---@field buf integer
---@field placement obsidian.img.Placement

---@type table<integer, obsidian.img.PreviewState>
local windows = {}
local installed = false

local function enabled()
  return Obsidian and Obsidian.opts and Obsidian.opts.img and Obsidian.opts.img.enabled == true
end

local function replace_lines(buf, lines)
  if not vim.api.nvim_buf_is_valid(buf) then
    return
  end
  local modifiable = vim.bo[buf].modifiable
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.bo[buf].modifiable = modifiable
end

local function close(win)
  local state = windows[win]
  if not state then
    return
  end
  windows[win] = nil
  state.owner:close()
  for _, other in pairs(windows) do
    if other.buf == state.buf then
      return
    end
  end
  if vim.api.nvim_buf_is_valid(state.buf) then
    replace_lines(state.buf, filetypes.info_lines(vim.api.nvim_buf_get_name(state.buf)))
  end
end

local function placement(win)
  local pos = vim.api.nvim_win_get_position(win)
  local config = vim.api.nvim_win_get_config(win)
  local border = config.border and #config.border > 0 and 1 or 0
  local width = vim.api.nvim_win_get_width(win)
  local height = vim.api.nvim_win_get_height(win)
  return {
    relative = "editor",
    row = pos[1] + border + 1,
    col = pos[2] + border + 1,
    max_width = math.max(1, width),
    max_height = math.max(1, height),
  }
end

---Synchronize one window with its marked preview buffer (if any).
---@param win integer
function M.refresh(win)
  if not vim.api.nvim_win_is_valid(win) then
    close(win)
    return
  end
  local buf = vim.api.nvim_win_get_buf(win)
  local path = enabled() and vim.api.nvim_buf_get_name(buf) or ""
  local is_preview = vim.bo[buf].buftype == "nofile" and filetypes.extension(path) == "png"
  local state = windows[win]
  if not is_preview then
    close(win)
    return
  end
  if state and state.buf ~= buf then
    close(win)
    state = windows[win]
  end
  if state then
    if state.owner.image_id then
      local next_placement = placement(win)
      if not vim.deep_equal(next_placement, state.placement) then
        local ok = state.owner:update(next_placement)
        if not ok then
          close(win)
        else
          state.placement = next_placement
        end
      end
    end
    return
  end

  local owner = require("obsidian.img").owner { kind = "picker-preview", win = win, buf = buf }
  state = { owner = owner, buf = buf, placement = placement(win) }
  windows[win] = state
  owner:show({ source = path, placement = state.placement }, function(ok, err)
    if windows[win] ~= state or not vim.api.nvim_win_is_valid(win) or vim.api.nvim_win_get_buf(win) ~= buf then
      return
    end
    if ok then
      replace_lines(buf, { "" })
    else
      -- Keep the failed state until the buffer leaves this window. Otherwise
      -- every scroll would retry an unsupported terminal or malformed file.
      owner:close()
      if vim.api.nvim_buf_is_valid(buf) then
        local lines = filetypes.info_lines(path)
        lines[1] = "Image preview unavailable: " .. tostring(err)
        replace_lines(buf, lines)
      end
    end
  end)
end

---Register autocmds once; called when a PNG path-preview buffer is created.
function M.setup()
  if installed then
    return
  end
  installed = true
  local group = vim.api.nvim_create_augroup("ObsidianImgPreview", { clear = true })
  vim.api.nvim_create_autocmd("BufWinEnter", {
    group = group,
    callback = function(ev)
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        if vim.api.nvim_win_get_buf(win) == ev.buf then
          M.refresh(win)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd({ "WinScrolled", "WinResized", "VimResized" }, {
    group = group,
    callback = function()
      for win in pairs(windows) do
        M.refresh(win)
      end
    end,
  })
  vim.api.nvim_create_autocmd("WinClosed", {
    group = group,
    callback = function(ev)
      close(tonumber(ev.match))
    end,
  })
  vim.api.nvim_create_autocmd({ "BufWipeout", "BufUnload" }, {
    group = group,
    callback = function(ev)
      for win, state in pairs(windows) do
        if state.buf == ev.buf then
          close(win)
        end
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabLeave", {
    group = group,
    callback = function()
      for win in pairs(windows) do
        close(win)
      end
    end,
  })
  vim.api.nvim_create_autocmd("TabEnter", {
    group = group,
    callback = function()
      for _, win in ipairs(vim.api.nvim_tabpage_list_wins(0)) do
        M.refresh(win)
      end
    end,
  })
end

return M
