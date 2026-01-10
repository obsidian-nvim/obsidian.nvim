local periodic = require "obsidian.periodic"
local log = require "obsidian.log"

local M = {}

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

-- Daily commands

---@param data obsidian.CommandArgs
M.today = function(data)
  local offset_days = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_days = offset
    end
  end
  local note = periodic.daily_fn(offset_days, {})
  note:open()
end

M.yesterday = function()
  local note = periodic.yesterday()
  note:open()
end

M.tomorrow = function()
  local note = periodic.tomorrow()
  note:open()
end

---@param data obsidian.CommandArgs
M.dailies = function(data)
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
      error ":Obsidian dailies expected at most 2 arguments"
    end
  end

  periodic.daily_pick(offset_start, offset_end, function(note)
    note:open()
  end)
end

-- Weekly commands

---@param data obsidian.CommandArgs
M.weekly = function(data)
  local offset_weeks = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_weeks = offset
    end
  end
  local note = periodic.weekly_fn(offset_weeks, {})
  note:open()
end

M.last_week = function()
  local note = periodic.last_week()
  note:open()
end

M.next_week = function()
  local note = periodic.next_week()
  note:open()
end

---@param data obsidian.CommandArgs
M.weeklies = function(data)
  local offset_start = -3
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
      error ":Obsidian weeklies expected at most 2 arguments"
    end
  end

  periodic.weekly:pick(offset_start, offset_end)
end

-- Monthly commands

---@param data obsidian.CommandArgs
M.monthly = function(data)
  local offset_months = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_months = offset
    end
  end
  local note = periodic.monthly_fn(offset_months, {})
  note:open()
end

M.last_month = function()
  local note = periodic.last_month()
  note:open()
end

M.next_month = function()
  local note = periodic.next_month()
  note:open()
end

---@param data obsidian.CommandArgs
M.monthlies = function(data)
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
      error ":Obsidian monthlies expected at most 2 arguments"
    end
  end

  periodic.monthly:pick(offset_start, offset_end)
end

-- Quarterly commands

---@param data obsidian.CommandArgs
M.quarterly = function(data)
  local offset_quarters = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_quarters = offset
    end
  end
  local note = periodic.quarterly_fn(offset_quarters, {})
  note:open()
end

M.last_quarter = function()
  local note = periodic.last_quarter()
  note:open()
end

M.next_quarter = function()
  local note = periodic.next_quarter()
  note:open()
end

---@param data obsidian.CommandArgs
M.quarterlies = function(data)
  local offset_start = -3
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
      error ":Obsidian quarterlies expected at most 2 arguments"
    end
  end

  periodic.quarterly:pick(offset_start, offset_end)
end

-- Yearly commands

---@param data obsidian.CommandArgs
M.yearly = function(data)
  local offset_years = 0
  local arg = string.gsub(data.args, " ", "")
  if string.len(arg) > 0 then
    local offset = tonumber(arg)
    if offset == nil then
      log.err "Invalid argument, expected an integer offset"
      return
    else
      offset_years = offset
    end
  end
  local note = periodic.yearly_fn(offset_years, {})
  note:open()
end

M.last_year = function()
  local note = periodic.last_year()
  note:open()
end

M.next_year = function()
  local note = periodic.next_year()
  note:open()
end

---@param data obsidian.CommandArgs
M.yearlies = function(data)
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

  periodic.yearly:pick(offset_start, offset_end)
end

return M
