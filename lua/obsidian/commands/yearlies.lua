local log = require "obsidian.log"
local yearly = require "obsidian.yearly"

---@param arg string
---@return number
local function parse_offset(arg)
  if vim.startswith(arg, "+") then
    return assert(tonumber(string.sub(arg, 2)), string.format("invalid offset '%s'", arg))
  elseif vim.startswith(arg, "-") then
    return -assert(tonumber(string.sub(arg, 2)), string.format("invalid offset '%s'", arg))
  else
    return assert(tonumber(arg), string.format("invalid offset '%s'", arg))
  end
end

---@param data obsidian.CommandArgs
return function(data)
  local offset_start = -5
  local offset_end = 0

  if data.fargs and #data.fargs > 0 then
    if #data.fargs == 1 then
      local offset = parse_offset(data.fargs[1])
      if offset >= 0 then
        offset_end = offset
      else
        offset_start = offset
      end
    elseif #data.fargs == 2 then
      local offsets = vim.tbl_map(parse_offset, data.fargs)
      table.sort(offsets)
      offset_start = offsets[1]
      offset_end = offsets[2]
    else
      error ":Obsidian yearlies expected at most 2 arguments"
    end
  end

  local picker = Obsidian.picker
  if not picker then
    log.err "No picker configured"
    return
  end

  ---@type obsidian.PickerEntry[]
  local yearlies = {}
  for offset = offset_end, offset_start, -1 do
    local now = os.time()
    local year = tonumber(os.date("%Y", now)) + offset
    local datetime = os.time({ year = year, month = 1, day = 1, hour = 0, min = 0, sec = 0 })
    local yearly_note_path = yearly.yearly_note_path(datetime)
    local yearly_note_alias = tostring(os.date(Obsidian.opts.yearly_notes.alias_format or "%Y", datetime))
    if offset == 0 then
      yearly_note_alias = yearly_note_alias .. " @this-year"
    elseif offset == -1 then
      yearly_note_alias = yearly_note_alias .. " @last-year"
    elseif offset == 1 then
      yearly_note_alias = yearly_note_alias .. " @next-year"
    end
    if not yearly_note_path:is_file() then
      yearly_note_alias = yearly_note_alias .. " ➡️ create"
    end
    yearlies[#yearlies + 1] = {
      value = offset,
      display = yearly_note_alias,
      ordinal = yearly_note_alias,
      filename = tostring(yearly_note_path),
    }
  end

  picker:pick(yearlies, {
    prompt_title = "Yearlies",
    callback = function(entry)
      local note = yearly.yearly(entry.value, {})
      note:open()
    end,
  })
end
