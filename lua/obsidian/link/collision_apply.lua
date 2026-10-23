local api = require "obsidian.api"
local log = require "obsidian.log"

local M = {}

local has_nvim_0_12 = vim.fn.has "nvim-0.12.0" == 1

---@param plan obsidian.link.CollisionPlan
---@param workspace_edit lsp.WorkspaceEdit?
local function preview(plan, workspace_edit)
  local items = {}
  if workspace_edit then
    for _, change in ipairs(workspace_edit.documentChanges or {}) do
      if change.textDocument then
        local path = vim.uri_to_fname(change.textDocument.uri)
        local lines = M.current_lines(path)
        for _, edit in ipairs(change.edits) do
          local start = edit.range.start
          local finish = edit.range["end"]
          items[#items + 1] = {
            filename = path,
            lnum = start.line + 1,
            col = start.character + 1,
            text = (lines[start.line + 1] or ""):sub(start.character + 1, finish.character) .. " → " .. edit.newText,
          }
        end
      end
    end
  else
    for path, edits in pairs(plan.edits) do
      for i, edit in ipairs(edits) do
        local original = assert(plan.original[path][i], "missing original link target")
        items[#items + 1] = {
          filename = path,
          lnum = original.row + 1,
          col = original.col + 1,
          text = original.text .. " → " .. edit.newText,
        }
      end
    end
  end
  vim.fn.setqflist({}, " ", { title = "Link collision repairs", items = items })
  vim.cmd.copen()
end

---@param plan obsidian.link.CollisionPlan
---@param opts { count: integer?, notes: integer?, edit: lsp.WorkspaceEdit?, rename: boolean? }?
---@return boolean
function M.confirm(plan, opts)
  if plan.count == 0 or Obsidian.opts.link.auto_update == true then
    return true
  end
  opts = opts or {}
  local prompt = ("Update %d links in %d notes? Open buffers will remain unsaved. Declining may change where short links lead."):format(
    opts.count or plan.count,
    opts.notes or plan.notes
  )
  while true do
    local choice = api.confirm(prompt, "&Yes\n&Inspect\n&No")
    if choice == "Yes" then
      return true
    elseif choice ~= "Inspect" then
      if opts.rename then
        log.info "Rename canceled; links unchanged"
      else
        log.warn("Left %d short links unchanged; they may now resolve to another note", plan.count)
      end
      return false
    end
    preview(plan, opts.edit)
  end
end

---@param path string
---@return string[]
function M.current_lines(path)
  local bufnr = vim.fn.bufnr(path)
  if bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr) then
    return vim.api.nvim_buf_get_lines(bufnr, 0, -1, false)
  end
  return vim.fn.readfile(path)
end

---@param plan obsidian.link.CollisionPlan
---@param path string
---@return boolean
local function still_current(plan, path)
  local lines = M.current_lines(path)
  for _, original in ipairs(plan.original[path]) do
    local line = lines[original.row + 1]
    if not line or line:sub(original.col + 1, original.col + #original.text) ~= original.text then
      return false
    end
  end
  return true
end

---@param path string
---@param edits lsp.TextEdit[] Sorted from later to earlier positions.
---@return table<integer, string>
function M.expected_lines(path, edits)
  local current = M.current_lines(path)
  local expected = {}
  for _, edit in ipairs(edits) do
    local row = edit.range.start.line + 1
    local line = assert(expected[row] or current[row], "link edit line is missing")
    local start_col, end_col = edit.range.start.character, edit.range["end"].character
    ---@cast start_col integer
    ---@cast end_col integer
    expected[row] = line:sub(1, start_col) .. edit.newText .. line:sub(end_col + 1)
  end
  return expected
end

---@param path string
---@param expected table<integer, string>
---@return boolean
function M.edits_applied(path, expected)
  local lines = M.current_lines(path)
  for row, line in pairs(expected) do
    if lines[row] ~= line then
      return false
    end
  end
  return true
end

---@param plan obsidian.link.CollisionPlan
---@param opts { rename: boolean? }?
---@return integer applied
---@return integer skipped
function M.apply(plan, opts)
  opts = opts or {}
  local document_changes = {}
  local loaded_before = {}
  local expected = {}
  local skipped = 0
  local paths = vim.tbl_keys(plan.edits)
  table.sort(paths)
  for _, path in ipairs(paths) do
    local bufnr = vim.fn.bufnr(path)
    local was_loaded = bufnr > 0 and vim.api.nvim_buf_is_loaded(bufnr)
    if
      not still_current(plan, path)
      or (was_loaded and (not vim.bo[bufnr].modifiable or vim.bo[bufnr].readonly))
      or (not was_loaded and vim.fn.filewritable(path) ~= 1)
    then
      skipped = skipped + #plan.edits[path]
    else
      loaded_before[path] = was_loaded
      local edits = vim.deepcopy(plan.edits[path])
      table.sort(edits, function(a, b)
        local x, y = a.range.start, b.range.start
        return x.line > y.line or (x.line == y.line and x.character > y.character)
      end)
      expected[path] = M.expected_lines(path, edits)
      document_changes[#document_changes + 1] = {
        textDocument = { uri = vim.uri_from_fname(path), version = has_nvim_0_12 and vim.NIL or nil },
        edits = edits,
      }
    end
  end
  if opts.rename and skipped > 0 then
    log.warn("Rename canceled: %d link edits became stale or read-only", skipped)
    return 0, skipped
  end
  if #document_changes == 0 then
    if skipped > 0 or plan.unresolved > 0 then
      log.warn("Skipped %d stale links; %d links had no provable prior target", skipped, plan.unresolved)
    end
    return 0, skipped
  end

  local ok, err = pcall(vim.lsp.util.apply_workspace_edit, { documentChanges = document_changes }, "utf-8")
  local applied, notes = 0, 0
  for _, path in ipairs(paths) do
    if loaded_before[path] ~= nil then
      local edits = plan.edits[path]
      if M.edits_applied(path, expected[path]) then
        applied = applied + #edits
        notes = notes + 1
        if not loaded_before[path] then
          local bufnr = vim.fn.bufnr(path)
          local saved, save_err = pcall(vim.api.nvim_buf_call, bufnr, function()
            vim.cmd "silent noautocmd write"
          end)
          if not saved then
            log.err("Could not save link repairs in '%s': %s", path, save_err)
          else
            vim.api.nvim_buf_delete(bufnr, { unload = true })
          end
        end
      else
        skipped = skipped + #edits
      end
    end
  end
  if not ok then
    log.err("Link repair workspace edit failed: %s", err)
  end
  if applied > 0 then
    log.info("Updated %d links in %d notes", applied, notes)
  end
  if skipped > 0 or plan.unresolved > 0 then
    log.warn("Skipped %d stale links; %d links had no provable prior target", skipped, plan.unresolved)
  end
  return applied, skipped
end

return M
