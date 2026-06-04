local M = {}

---@param occ obsidian.agenda.Occurrence
---@return string
local function marker(occ)
  if occ.kind == "scheduled" then
    return "S"
  elseif occ.kind == "due" then
    return "D"
  elseif occ.kind == "overdue" then
    return "!"
  elseif occ.kind == "undated" then
    return "?"
  else
    return "-"
  end
end

---@param section obsidian.agenda.Section
---@param occ obsidian.agenda.Occurrence
---@return string
local function render_text(section, occ)
  local item = occ.item
  local pieces = { "[", section.title, "] ", marker(occ), " " }
  if item.priority then
    pieces[#pieces + 1] = string.format("[#%s] ", item.priority)
  end
  pieces[#pieces + 1] = item.title or ""
  return table.concat(pieces)
end

---@param title string
---@param items vim.quickfix.entry[]
---@return integer
local function set_qflist(title, items)
  vim.fn.setqflist({}, "r", { title = title, items = items })
  vim.cmd "copen"

  local qf = vim.fn.getqflist { winid = 0 }
  if qf.winid and qf.winid ~= 0 then
    return vim.api.nvim_win_get_buf(qf.winid)
  end
  return vim.api.nvim_get_current_buf()
end

---@param _state table
---@return integer
M.loading = function(_state)
  return set_qflist("Obsidian Agenda", {
    { text = "Loading agenda...", valid = 0 },
  })
end

---@param _bufnr integer
---@param view obsidian.agenda.View
---@param state table
M.render = function(_bufnr, view, state)
  local items = {}

  for _, section in ipairs(view.sections) do
    for _, occ in ipairs(section.items) do
      local item = occ.item
      items[#items + 1] = {
        filename = item.path,
        lnum = item.lnum or 1,
        col = item.col or 1,
        text = render_text(section, occ),
        user_data = {
          obsidian_agenda_item = item,
          obsidian_agenda_occurrence = occ,
        },
      }
    end
  end

  if #items == 0 then
    items[#items + 1] = { text = "No agenda items.", valid = 0 }
  end

  state.view_name = view.name
  set_qflist(view.title, items)
end

---@param _bufnr integer
---@param message string
---@param _state table
M.error = function(_bufnr, message, _state)
  set_qflist("Obsidian Agenda", {
    { text = "Agenda error:", valid = 0 },
    { text = message, valid = 0 },
  })
end

return M
