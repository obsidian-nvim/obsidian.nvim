local M = {}

local Note = require "obsidian.note"
local search = require "obsidian.search"
local util = require "obsidian.util"

function _G.ObsidianFoldexpr(lnum)
  local bufnr = vim.api.nvim_get_current_buf()
  local tick = vim.b[bufnr].changedtick
  local fold_yaml = not not vim.g.obsidian_fold_yaml
  local cache = vim.b[bufnr]._obs_md_fold_cache

  if not cache or cache.tick ~= tick or cache.fold_yaml ~= fold_yaml then
    local lines = vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
    local levels = {}
    local blocks = search.find_code_blocks(lines)
    local block_idx = 1
    local block = blocks[block_idx]
    local in_tilde_fence = false

    local function is_frontmatter_boundary(line)
      return Note._is_frontmatter_boundary(vim.trim(line))
    end

    -- Detect YAML frontmatter only if the file starts with '---' (after blanks)
    local first = 1
    while first <= #lines and lines[first]:match "^%s*$" do
      first = first + 1
    end
    local frontmatter_start = first <= #lines and is_frontmatter_boundary(lines[first]) and first or nil
    local in_frontmatter = frontmatter_start ~= nil

    local cur = 0

    for i, line in ipairs(lines) do
      while block and i > block[2] do
        block_idx = block_idx + 1
        block = blocks[block_idx]
      end

      local in_backtick_block = block and i >= block[1] and i <= block[2]

      if in_frontmatter and i >= (frontmatter_start or 0) then
        if fold_yaml then
          levels[i] = i == frontmatter_start and ">1" or 1
        else
          levels[i] = 0
        end
        if i ~= frontmatter_start and is_frontmatter_boundary(line) then
          in_frontmatter = false
        end
      elseif not in_backtick_block and line:match "^%s*~~~" then
        in_tilde_fence = not in_tilde_fence
        levels[i] = cur
      elseif in_backtick_block or in_tilde_fence then
        levels[i] = cur
      else
        local header = util.parse_header(line)
        if header then
          cur = math.min(header.level, 6)
          levels[i] = ">" .. cur
        else
          levels[i] = cur
        end
      end
    end

    cache = { tick = tick, fold_yaml = fold_yaml, levels = levels }
    vim.b[bufnr]._obs_md_fold_cache = cache
  end

  return cache.levels[lnum] or 0
end

local function save_window_foldopts_for_buffer(winid, bufnr)
  vim.w[winid]._obs_cycle_saved = vim.w[winid]._obs_cycle_saved or {}
  if vim.w[winid]._obs_cycle_saved[bufnr] then
    return
  end

  local function getopt(name)
    return vim.api.nvim_get_option_value(name, { win = winid })
  end

  local saved = {
    foldenable = getopt "foldenable",
    foldlevel = getopt "foldlevel",
    foldmethod = getopt "foldmethod",
    foldexpr = getopt "foldexpr",
    view = vim.fn.winsaveview(),
  }
  vim.w[winid]._obs_cycle_saved[bufnr] = saved

  -- Restore when this buffer leaves THIS window, so other buffers aren't affected.
  vim.api.nvim_create_autocmd("BufWinLeave", {
    buffer = bufnr,
    callback = function()
      if not vim.api.nvim_win_is_valid(winid) then
        return
      end
      for k, v in pairs(saved) do
        if k ~= "view" then
          vim.api.nvim_set_option_value(k, v, { win = winid })
        end
      end
      vim.api.nvim_win_call(winid, function()
        vim.fn.winrestview(saved.view)
      end)
      vim.w[winid]._obs_cycle_saved[bufnr] = nil
    end,
  })
end

local function apply_markdown_heading_folds(winid, bufnr)
  if vim.bo[bufnr].filetype ~= "markdown" then
    return
  end
  vim.api.nvim_set_option_value("foldmethod", "expr", { win = winid })
  vim.api.nvim_set_option_value("foldexpr", "v:lua.ObsidianFoldexpr(v:lnum)", { win = winid })
end

--- Adapted from `nvim-orgmode/orgmode`
--- Cycle all headings in file between "Show All", "Contents" and "Overview"
M.cycle_global = function()
  local bufnr = vim.api.nvim_get_current_buf()
  local winid = vim.api.nvim_get_current_win()

  -- buffer-local mode (no leaking across files)
  local mode = vim.b[bufnr].obsidian_cycle_mode or "Show All"

  save_window_foldopts_for_buffer(winid, bufnr)

  -- avoid YAML list folds by using heading-only folding in markdown
  apply_markdown_heading_folds(winid, bufnr)

  -- enable folding while cycling (restored on BufWinLeave)
  vim.api.nvim_set_option_value("foldenable", true, { win = winid })

  if mode == "Show All" then
    mode = "Overview"
    vim.cmd "silent! normal! zMzX"
  elseif mode == "Contents" then
    mode = "Show All"
    vim.cmd "silent! normal! zR"
  else
    mode = "Contents"
    vim.api.nvim_set_option_value("foldlevel", 1, { win = winid })
    vim.cmd "silent! normal! zx"
  end

  vim.b[bufnr].obsidian_cycle_mode = mode
  vim.api.nvim_echo({ { "Obsidian: " .. mode } }, false, {})
end

return M
