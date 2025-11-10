local M = {}
local obsidian = require "obsidian"
local search = obsidian.search
local RefTypes = search.RefTypes

---@param note obsidian.Note
---@return vim.Diagnostic.Set[]
local function links_diag(note)
  local links = note:links()

  local diags = {}

  for _, link_match in ipairs(links) do
    local location, _, t = obsidian.util.parse_link(link_match.link, { strip = true })

    if location and (t == RefTypes.Wiki or t == RefTypes.WikiWithAlias or t == RefTypes.Markdown) then
      local notes = search.resolve_note(location)
      if vim.tbl_isempty(notes) then
        diags[#diags + 1] = {
          lnum = link_match.line - 1,
          message = "Dead link",
          severity = vim.diagnostic.severity.HINT,
        }
      end
    end
  end
  return diags
end

---@param note obsidian.Note
---@return vim.Diagnostic.Set[]
local function backlinks_diag(note)
  local backlinks = note:backlinks {}
  if #backlinks == 0 then
    return {
      {
        lnum = 1,
        severity = vim.diagnostic.severity.HINT,
        message = "Orphan Note",
      },
    }
  end
  return {}
end

---@param ev vim.api.keyset.create_autocmd.callback_args
local function run_diagnostics(ev)
  local ns = vim.api.nvim_create_namespace("obsidian-ls-diagnostics-" .. ev.buf)

  local note = obsidian.Note.from_buffer(ev.buf)
  local diags = {}

  vim.list_extend({}, links_diag(note)) -- on textchanged
  vim.list_extend(diags, backlinks_diag(note)) -- on other files changed ?

  vim.diagnostic.set(ns, ev.buf, diags, {})
end

M.setup = function()
  vim.api.nvim_create_autocmd("User", { -- TODO: event
    pattern = "ObsidianNoteEnter",
    callback = run_diagnostics,
  })
end

return M
