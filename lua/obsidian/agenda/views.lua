local dates = require "obsidian.agenda.dates"

local M = {}

local priority_rank = { A = 1, B = 2, C = 3 }

---@param item obsidian.agenda.Item
---@return integer
local function item_rank(item)
  return priority_rank[item.priority or ""] or 9
end

---@param a obsidian.agenda.Occurrence
---@param b obsidian.agenda.Occurrence
---@return boolean
local function occurrence_less(a, b)
  local ad = a.date or a.item.due or a.item.scheduled or a.item.date or math.huge
  local bd = b.date or b.item.due or b.item.scheduled or b.item.date or math.huge
  if ad ~= bd then
    return ad < bd
  end
  local ap, bp = item_rank(a.item), item_rank(b.item)
  if ap ~= bp then
    return ap < bp
  end
  if (a.item.path or "") ~= (b.item.path or "") then
    return (a.item.path or "") < (b.item.path or "")
  end
  return (a.item.lnum or 0) < (b.item.lnum or 0)
end

---@param items obsidian.agenda.Item[]
---@param show_done boolean|nil
---@return obsidian.agenda.Item[]
local function filter_items(items, show_done)
  if show_done then
    return items
  end
  return vim.tbl_filter(function(item)
    return item.status ~= "done"
  end, items)
end

---@param sections obsidian.agenda.Section[]
local function sort_sections(sections)
  for _, section in ipairs(sections) do
    table.sort(section.items, occurrence_less)
  end
  table.sort(sections, function(a, b)
    if a.title == "Overdue" then
      return true
    elseif b.title == "Overdue" then
      return false
    elseif a.title == "Undated" then
      return false
    elseif b.title == "Undated" then
      return true
    elseif a.date and b.date then
      return a.date < b.date
    else
      return a.title < b.title
    end
  end)
end

---@param item obsidian.agenda.Item
---@return boolean
local function has_dated_signal(item)
  return item.date ~= nil or item.due ~= nil or item.scheduled ~= nil
end

---@param item obsidian.agenda.Item
---@param from integer
---@param to integer
---@param today integer
---@return obsidian.agenda.Occurrence[]
local function occurrences_for_range(item, from, to, today)
  local out = {}
  local function add(t, kind)
    if t and t >= from and t <= to then
      out[#out + 1] = { item = item, date = t, kind = kind }
    end
  end

  add(item.date, "date")
  add(item.scheduled, "scheduled")
  add(item.due, "due")

  if item.due and item.due < today and item.status ~= "done" then
    out[#out + 1] = { item = item, date = item.due, kind = "overdue" }
  end

  return out
end

---@param title string
---@param date integer|nil
---@return obsidian.agenda.Section
local function section(title, date)
  return { title = title, date = date, items = {} }
end

---@param items obsidian.agenda.Item[]
---@param opts table
---@return obsidian.agenda.Section[]
local function build_period_sections(items, opts)
  local from, to = opts.from, opts.to
  local today = dates.start_of_day(os.time())
  local include_empty = opts.include_empty == true
  local show_undated = opts.show_undated == true
  local by_key = {}
  local sections = {}

  if opts.show_overdue then
    local overdue = section("Overdue", nil)
    for _, item in ipairs(items) do
      if item.due and item.due < today and item.status ~= "done" then
        overdue.items[#overdue.items + 1] = { item = item, date = item.due, kind = "overdue" }
      end
    end
    if #overdue.items > 0 then
      sections[#sections + 1] = overdue
    end
  end

  local day = from
  while day <= to do
    local title = dates.format_day(day)
    if dates.same_day(day, today) then
      title = "Today " .. title
    end
    local s = section(title, day)
    by_key[dates.key(day)] = s
    if include_empty then
      sections[#sections + 1] = s
    end
    day = dates.add_days(day, 1)
  end

  for _, item in ipairs(items) do
    for _, occ in ipairs(occurrences_for_range(item, from, to, today)) do
      if occ.kind ~= "overdue" then
        local s = by_key[dates.key(occ.date)]
        if s then
          s.items[#s.items + 1] = occ
          if not include_empty and not vim.list_contains(sections, s) then
            sections[#sections + 1] = s
          end
        end
      end
    end
  end

  if show_undated then
    local undated = section("Undated", nil)
    for _, item in ipairs(items) do
      if not has_dated_signal(item) then
        undated.items[#undated.items + 1] = { item = item, date = nil, kind = "undated" }
      end
    end
    if #undated.items > 0 then
      sections[#sections + 1] = undated
    end
  end

  sort_sections(sections)
  return sections
end

---@param items obsidian.agenda.Item[]
---@param base_date integer|nil
---@return obsidian.agenda.View
M.week = function(items, base_date)
  local opts = Obsidian.opts.agenda.views.week
  local start = dates.start_of_week(base_date or os.time(), Obsidian.opts.date.start_of_week)
  local finish = dates.add_days(start, (opts.span or 7) - 1)
  items = filter_items(items, opts.show_done)
  return {
    name = "week",
    title = "Obsidian Agenda: Week of " .. dates.format(start),
    range = { from = start, to = finish },
    sections = build_period_sections(items, {
      from = start,
      to = finish,
      show_overdue = opts.show_overdue,
      show_undated = opts.show_undated,
    }),
  }
end

---@param items obsidian.agenda.Item[]
---@param base_date integer|nil
---@return obsidian.agenda.View
M.day = function(items, base_date)
  local opts = Obsidian.opts.agenda.views.day
  local day = dates.start_of_day(base_date or os.time())
  items = filter_items(items, opts.show_done)
  return {
    name = "day",
    title = "Obsidian Agenda: " .. dates.format(day),
    range = { from = day, to = day },
    sections = build_period_sections(items, {
      from = day,
      to = day,
      show_overdue = opts.show_overdue,
      show_undated = opts.show_undated,
      include_empty = true,
    }),
  }
end

---@param items obsidian.agenda.Item[]
---@return obsidian.agenda.View
M.todo = function(items)
  local opts = Obsidian.opts.agenda.views.todo
  local occs = {}
  for _, item in ipairs(filter_items(items, opts.show_done)) do
    occs[#occs + 1] = {
      item = item,
      date = item.due or item.scheduled or item.date,
      kind = has_dated_signal(item) and "date" or "undated",
    }
  end
  table.sort(occs, occurrence_less)
  return {
    name = "todo",
    title = "Obsidian Agenda: Todo",
    range = {},
    sections = { { title = "Todo", items = occs } },
  }
end

---@param items obsidian.agenda.Item[]
---@param base_date integer|nil
---@return obsidian.agenda.View
M.month = function(items, base_date)
  local opts = Obsidian.opts.agenda.views.month
  local start = dates.start_of_month(base_date or os.time())
  local finish = dates.add_days(start, dates.days_in_month(start) - 1)
  items = filter_items(items, opts.show_done)
  return {
    name = "month",
    title = "Obsidian Agenda: " .. dates.format_month(start),
    range = { from = start, to = finish },
    sections = build_period_sections(items, {
      from = start,
      to = finish,
      show_overdue = opts.show_overdue,
      show_undated = opts.show_undated,
    }),
  }
end

---@param items obsidian.agenda.Item[]
---@param base_date integer|nil
---@return obsidian.agenda.View
M.year = function(items, base_date)
  local opts = Obsidian.opts.agenda.views.year
  local start = dates.start_of_year(base_date or os.time())
  local d = os.date("*t", start)
  ---@cast d osdateparam
  d.month, d.day, d.hour, d.min, d.sec = 12, 31, 12, 0, 0
  local finish = os.time(d)
  items = filter_items(items, opts.show_done)
  return {
    name = "year",
    title = "Obsidian Agenda: " .. dates.format_year(start),
    range = { from = start, to = finish },
    sections = build_period_sections(items, {
      from = start,
      to = finish,
      show_overdue = opts.show_overdue,
      show_undated = opts.show_undated,
    }),
  }
end

---@param name string
---@param items obsidian.agenda.Item[]
---@param base_date integer|nil
---@return obsidian.agenda.View
M.build = function(name, items, base_date)
  name = name or Obsidian.opts.agenda.default_view or "week"
  local fn = M[name]
  if not fn then
    error("Unknown agenda view: " .. tostring(name))
  end
  return fn(items, base_date)
end

return M
