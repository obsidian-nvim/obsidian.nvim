local log = require "obsidian.log"
local Path = require "obsidian.path"
local picker = require "obsidian.picker"
local util = require "obsidian.util"

local M = {}

---@class obsidian.resolver.AttachmentCtx
---@field bufnr integer
---@field source string|?
---@field intent string

---@class obsidian.resolver.AttachmentResult
---@field path string Local filepath, file URI, or URL accepted by `obsidian.attachment.add`.

---@class obsidian.resolver.DateCtx
---@field intent string
---@field cadence string|?
---@field offset_start integer|?
---@field offset_end integer|?
---@field default_timestamp integer|?

---@class obsidian.resolver.DateResult
---@field timestamp integer Unix timestamp.
---@field precision string|?
---@field label string|?
---@field offset integer|?

---@alias obsidian.Resolver fun(ctx: table, done: fun(result: table|?, err: string|?))

---@type table<string, obsidian.Resolver>
M.builtin = {}

---@param src string
---@param done fun(result: obsidian.resolver.AttachmentResult|?, err: string|?)
local function resolve_attachment_source(src, done)
  src = vim.trim(src)
  if src == "" then
    done(nil)
    return
  end

  local is_uri, scheme = util.is_uri(src)
  if is_uri and scheme then
    if scheme == "http" or scheme == "https" then
      done { path = src }
    elseif scheme == "file" then
      done { path = vim.uri_to_fname(src) }
    else
      done(nil, "Unknown URI format")
    end
    return
  end

  local expanded = vim.fn.expand(src)
  ---@cast expanded string
  local path = vim.fs.normalize(vim.fn.fnamemodify(expanded, ":p"))
  local stat = vim.uv.fs_stat(path)
  if stat and stat.type == "directory" then
    picker.find_files {
      dir = path,
      include_non_markdown = true,
      callback = function(p)
        done { path = p }
      end,
    }
  else
    done { path = path }
  end
end

---@type obsidian.Resolver
M.builtin.attachment = function(ctx, done)
  if ctx.source ~= nil and vim.trim(ctx.source) ~= "" then
    resolve_attachment_source(ctx.source, done)
    return
  end

  vim.ui.input({ prompt = "Url or filepath", completion = "file" }, function(input)
    if not input then
      done(nil)
      return
    end
    resolve_attachment_source(input, done)
  end)
end

---@param datetime integer
---@return obsidian.Path
local function daily_note_path(datetime)
  local path = Path.new(Obsidian.dir)
  local options = Obsidian.opts

  if options.daily_notes.folder ~= nil then
    path = path / options.daily_notes.folder
  elseif options.notes_subdir ~= nil then
    path = path / options.notes_subdir
  end

  local date_format = assert(options.daily_notes.date_format, "daily notes date_format is required")
  local daily_path = path / (tostring(util.format_date(datetime, date_format)) .. ".md")
  ---@cast daily_path obsidian.Path
  return daily_path
end

---@type obsidian.Resolver
M.builtin.date = function(ctx, done)
  if ctx.offset_start == nil or ctx.offset_end == nil then
    done {
      timestamp = ctx.default_timestamp or os.time(),
      precision = "day",
    }
    return
  end

  ---@type obsidian.PickerEntry[]
  local dailies = {}
  for offset = ctx.offset_end, ctx.offset_start, -1 do
    local datetime = os.time() + (offset * 3600 * 24)
    local daily_path = daily_note_path(datetime)
    local label = tostring(util.format_date(datetime, Obsidian.opts.daily_notes.alias_format or "%A %B %-d, %Y"))
    if offset == 0 then
      label = label .. " @today"
    elseif offset == -1 then
      label = label .. " @yesterday"
    elseif offset == 1 then
      label = label .. " @tomorrow"
    end
    if not daily_path:is_file() then
      label = label .. " ➡️ create"
    end
    dailies[#dailies + 1] = {
      user_data = {
        offset = offset,
        timestamp = datetime,
        label = label,
      },
      text = label,
      filename = tostring(daily_path),
    }
  end

  Obsidian.picker.pick(dailies, {
    prompt_title = "Dailies",
    callback = function(entry)
      ---@cast entry { user_data: { timestamp: integer, label: string, offset: integer } }
      done {
        timestamp = entry.user_data.timestamp,
        precision = "day",
        label = entry.user_data.label,
        offset = entry.user_data.offset,
      }
    end,
  })
end

---@param name string
---@param ctx table|?
---@param done fun(result: table|?, err: string|?)
M.resolve = function(name, ctx, done)
  ctx = ctx or {}
  local resolver = Obsidian.opts.resolvers and Obsidian.opts.resolvers[name] or nil
  resolver = resolver or M.builtin[name]
  if not resolver then
    local err = "No resolver registered for '" .. name .. "'"
    log.err(err)
    done(nil, err)
    return
  end

  local called = false
  local function once(result, err)
    if called then
      return
    end
    called = true
    if err then
      log.err(err)
    end
    done(result, err)
  end

  local ok, err = pcall(resolver, ctx, once)
  if not ok then
    once(nil, tostring(err))
  end
end

return M
