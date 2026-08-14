-- Templater Engine for obsidian.nvim
-- Implements a Lua-compatible subset of the Templater (Obsidian plugin) API
-- See: https://silentvoid13.github.io/Templater/

local util = require "obsidian.util"
local Path = require "obsidian.path"
local Note = require "obsidian.note"
local api = require "obsidian.api"
local log = require "obsidian.log"

local M = {}

-- Cache for user scripts
local user_scripts_cache = {}

---Get the user scripts folder from config
---@return obsidian.Path|?
local function get_user_scripts_folder()
  local opts = Obsidian.opts.templater
  if opts and opts.user_scripts_folder then
    return Path.new(opts.user_scripts_folder)
  end
  return nil
end

---@class obsidian.TemplaterContext
---@field type "insert_template" | "clone_template"
---@field template_name string|obsidian.Path
---@field templates_dir obsidian.Path|?
---@field location [integer, integer, integer, integer]?
---@field partial_note obsidian.Note|?
---@field destination_path obsidian.Path|?
---@field date string
---@field time string

---@class obsidian.TPDate
local TPDate = {}

---Format a date using moment.js-style tokens
---@param format string|?
---@return string
function TPDate.now(format)
  local moment = require "obsidian.lib.moment"
  local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
  return moment.format(os.time(), format or date_format)
end

---@param format string|?
---@param offset_days integer|?
---@return string
function TPDate.tomorrow(format, offset_days)
  local moment = require "obsidian.lib.moment"
  offset_days = offset_days or 1
  local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
  return moment.format(os.time() + (offset_days * 86400), format or date_format)
end

---@param format string|?
---@param offset_days integer|?
---@return string
function TPDate.yesterday(format, offset_days)
  local moment = require "obsidian.lib.moment"
  offset_days = offset_days or 1
  local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
  return moment.format(os.time() - (offset_days * 86400), format or date_format)
end

---@param format string|?
---@return string
function TPDate.weekday(format)
  local moment = require "obsidian.lib.moment"
  return moment.format(os.time(), format or "dddd")
end

---@param format string|?
---@return string
function TPDate.month(format)
  local moment = require "obsidian.lib.moment"
  return moment.format(os.time(), format or "MMMM")
end

---@param format string|?
---@return string
function TPDate.year(format)
  local moment = require "obsidian.lib.moment"
  return moment.format(os.time(), format or "YYYY")
end

---@param days integer
---@param format string|?
---@return string
function TPDate.day_offset(days, format)
  local moment = require "obsidian.lib.moment"
  local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
  return moment.format(os.time() + (days * 86400), format or date_format)
end

---@param format string|?
---@return string
function TPDate.now_utc(format)
  local moment = require "obsidian.lib.moment"
  local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
  return moment.format_utc(os.time(), format or date_format)
end

---@param format string|?
---@return string
function TPDate.time(format)
  local moment = require "obsidian.lib.moment"
  local time_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.time_format) or "HH:mm"
  return moment.format(os.time(), format or time_format)
end

---@param format string|?
---@return string
function TPDate.time_utc(format)
  local moment = require "obsidian.lib.moment"
  local time_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.time_format) or "HH:mm"
  return moment.format_utc(os.time(), format or time_format)
end

---@class obsidian.TPFile
local TPFile = {}

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.title(ctx)
  if ctx.partial_note then
    return ctx.partial_note.title or ""
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.path(ctx)
  if ctx.partial_note and ctx.partial_note.path then
    return tostring(ctx.partial_note.path)
  end
  if ctx.destination_path then
    return tostring(ctx.destination_path)
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.folder(ctx)
  local path = TPFile.path(ctx)
  if path and path ~= "" then
    return vim.fs.dirname(path)
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.name(ctx)
  local path = TPFile.path(ctx)
  if path and path ~= "" then
    return vim.fs.basename(path)
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.ext(ctx)
  local name = TPFile.name(ctx)
  return vim.fs.extension(name) or ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.root(ctx)
  if ctx.templates_dir then
    return tostring(ctx.templates_dir:parent())
  end
  if ctx.partial_note and ctx.partial_note.path then
    return tostring(ctx.partial_note.path:parent())
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.creation_date(ctx)
  if ctx.partial_note and ctx.partial_note.created_time then
    local moment = require "obsidian.lib.moment"
    local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
    return moment.format(ctx.partial_note.created_time, date_format)
  end
  return TPDate.now()
end

---@param ctx obsidian.TemplaterContext
---@param format string|?
---@return string
function TPFile.creation_date_format(ctx, format)
  if ctx.partial_note and ctx.partial_note.created_time then
    local moment = require "obsidian.lib.moment"
    return moment.format(ctx.partial_note.created_time, format)
  end
  local moment = require "obsidian.lib.moment"
  return moment.format(os.time(), format)
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.modification_date(ctx)
  if ctx.partial_note and ctx.partial_note.modified_time then
    local moment = require "obsidian.lib.moment"
    local date_format = (Obsidian and Obsidian.opts and Obsidian.opts.templates and Obsidian.opts.templates.date_format) or "YYYY-MM-DD"
    return moment.format(ctx.partial_note.modified_time, date_format)
  end
  return TPDate.now()
end

---@param ctx obsidian.TemplaterContext
---@param format string|?
---@return string
function TPFile.modification_date_format(ctx, format)
  if ctx.partial_note and ctx.partial_note.modified_time then
    local moment = require "obsidian.lib.moment"
    return moment.format(ctx.partial_note.modified_time, format)
  end
  local moment = require "obsidian.lib.moment"
  return moment.format(os.time(), format)
end

---@param ctx obsidian.TemplaterContext
---@return string[]
function TPFile.tags(ctx)
  if ctx.partial_note then
    return ctx.partial_note.tags or {}
  end
  return {}
end

---@param ctx obsidian.TemplaterContext
---@param tag string
---@return boolean
function TPFile.has_tag(ctx, tag)
  local tags = TPFile.tags(ctx)
  return vim.tbl_contains(tags, tag)
end

---@param ctx obsidian.TemplaterContext
---@return string[]
function TPFile.aliases(ctx)
  if ctx.partial_note then
    return ctx.partial_note.aliases or {}
  end
  return {}
end

---@param ctx obsidian.TemplaterContext
---@return string[]
function TPFile.links(ctx)
  if ctx.partial_note then
    return ctx.partial_note.links or {}
  end
  return {}
end

---@param ctx obsidian.TemplaterContext
---@return string[]
function TPFile.backlinks(ctx)
  if ctx.partial_note then
    return ctx.partial_note.backlinks or {}
  end
  return {}
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.content(ctx)
  if ctx.partial_note then
    return ctx.partial_note.content or ""
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.folder(ctx)
  if ctx.partial_note and ctx.partial_note.path then
    return ctx.partial_note.path:parent().filename
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@return string
function TPFile.frontmatter(ctx)
  if ctx.partial_note then
    return ctx.partial_note.frontmatter or ""
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@param key string
---@return any
function TPFile.property(ctx, key)
  if ctx.partial_note and ctx.partial_note.frontmatter then
    return ctx.partial_note.frontmatter[key]
  end
  return nil
end

---@param ctx obsidian.TemplaterContext
---@param name string
---@param content string
---@return obsidian.Note
function TPFile.create_new(ctx, name, content)
  local note = Note.new(name, {}, {})
  note.content = content
  return note
end

---@param ctx obsidian.TemplaterContext
---@param path string
---@return boolean
function TPFile.exists(ctx, path)
  local p = Path.new(path)
  return p:exists()
end

---@param ctx obsidian.TemplaterContext
---@param path string
---@return string
function TPFile.read(ctx, path)
  local p = Path.new(path)
  if p:is_file() then
    local content = p:read()
    return content or ""
  end
  return ""
end

---@param ctx obsidian.TemplaterContext
---@param path string
---@param content string
---@return boolean
function TPFile.write(ctx, path, content)
  local p = Path.new(path)
  p:parent():mkdir { parents = true, exist_ok = true }
  return p:write(content) == nil
end

---@class obsidian.TPSystem
local TPSystem = {}

---@param prompt string
---@param default string|?
---@return string
function TPSystem.prompt(prompt, default)
  local input = vim.fn.input(prompt .. (default and (" [" .. default .. "]") or "") .. ": ")
  if input == "" and default then
    return default
  end
  return input
end

---@param prompt string
---@param options string[]
---@param default integer|?
---@return string
function TPSystem.suggester(prompt, options, default)
  if vim.tbl_isempty(options) then
    return ""
  end

  local choice = vim.fn.inputlist(vim.list_extend({ prompt }, options))
  if choice >= 1 and choice <= #options then
    return options[choice]
  end
  if default and default >= 1 and default <= #options then
    return options[default]
  end
  return options[1]
end

---@param text string
---@return string
function TPSystem.clipboard(text)
  if text then
    vim.fn.setreg("+", text)
    return text
  end
  return vim.fn.getreg("+")
end

---@param cmd string
---@return string
function TPSystem.exec(cmd)
  local result = vim.system({ "sh", "-c", cmd }, { text = true }):wait()
  return result.stdout or ""
end

---@param seconds number
function TPSystem.sleep(seconds)
  vim.wait(math.floor(seconds * 1000))
end

---@return string
function TPSystem.env()
  return vim.inspect(vim.fn.environ())
end

---@param key string
---@return string
function TPSystem.get_env(key)
  return vim.fn.getenv(key) or ""
end

---@param key string
---@param value string
function TPSystem.set_env(key, value)
  vim.fn.setenv(key, value)
end

---@class obsidian.TPWeb
local TPWeb = {}

---@return string
function TPWeb.daily_quote()
  -- Simple local quotes - in real Templater this fetches from an API
  local quotes = {
    "The only way to do great work is to love what you do. — Steve Jobs",
    "Code is like humor. When you have to explain it, it's bad. — Cory House",
    "First, solve the problem. Then, write the code. — John Johnson",
    "Experience is the name everyone gives to their mistakes. — Oscar Wilde",
    "Simplicity is the soul of efficiency. — Austin Freeman",
  }
  return quotes[math.random(#quotes)]
end

---@param query string
---@param orientation string|?
---@return string
function TPWeb.random_picture(query, orientation)
  -- Returns a placeholder URL - real Templater fetches from Unsplash
  orientation = orientation or "landscape"
  return string.format("https://source.unsplash.com/random/%s?%s", orientation, query)
end

---@param url string
---@return string
function TPWeb.download_file(url)
  -- Would need curl/wget - return empty for now
  log.warn("tp.web.download_file not fully implemented")
  return ""
end

---@class obsidian.TPUser
local TPUser = {}

---Load user scripts from the configured scripts folder
---@param scripts_folder obsidian.Path
---@return table
local function load_user_scripts(scripts_folder)
  if not user_scripts_cache[scripts_folder] then
    local scripts = {}
    if scripts_folder and scripts_folder:exists() and scripts_folder:is_dir() then
      for file, ftype in scripts_folder:iter() do
        if ftype == "file" and vim.endswith(file:lower(), ".lua") then
          local name = vim.fs.basename(tostring(file))
          name = vim.fn.fnamemodify(name, ":r") -- remove extension
          local ok, module = pcall(dofile, tostring(file))
          if ok and type(module) == "table" then
            scripts[name] = module
          elseif ok then
            -- If it returns a function, wrap it
            scripts[name] = { run = module }
          else
            log.warn("Failed to load user script %s: %s", name, module)
          end
        end
      end
    end
    user_scripts_cache[scripts_folder] = scripts
  end
  return user_scripts_cache[scripts_folder]
end

---@param ctx obsidian.TemplaterContext
---@param script_name string
---@param ... any
---@return any
function TPUser.run_script(ctx, script_name, ...)
  local scripts_folder = get_user_scripts_folder()
  if not scripts_folder then
    log.warn("templater.user_scripts_folder not configured")
    return nil
  end

  local scripts = load_user_scripts(scripts_folder)
  local script = scripts[script_name]
  if not script then
    log.warn("User script '%s' not found in %s", script_name, scripts_folder)
    return nil
  end

  -- Pass context as first argument like Templater does
  local args = { ctx, ... }
  if type(script) == "function" then
    return script(unpack(args))
  elseif type(script) == "table" and type(script.run) == "function" then
    return script.run(unpack(args))
  end
  return nil
end

---@param ctx obsidian.TemplaterContext
---@param script_name string
---@return boolean
function TPUser.has_script(ctx, script_name)
  local scripts_folder = get_user_scripts_folder()
  if not scripts_folder then
    return false
  end
  local scripts = load_user_scripts(scripts_folder)
  return scripts[script_name] ~= nil
end

---@class obsidian.TP
local TP = {
  date = TPDate,
  file = TPFile,
  system = TPSystem,
  web = TPWeb,
  user = TPUser,
}

---Execute a template string with Templater-style `<% %>` and `<%= %>` tags
---@param template string
---@param ctx obsidian.TemplaterContext
---@return string
function M.execute_template(template, ctx)
  -- Set up the environment with tp.* functions bound to context
  -- Inherit from _G so require, os, string, etc. are available
  local env = setmetatable({
    tp = setmetatable({}, {
      __index = function(_, key)
        if TP[key] then
          -- Expose functions directly; templates pass ctx as first argument
          if key == "file" then
            return setmetatable({}, {
              __index = function(_, fname)
                return TPFile[fname]
              end
            })
          end
          return TP[key]
        end
        return nil
      end
    }),
    -- Also expose top-level for convenience
    date = TPDate,
    file = setmetatable({}, {
      __index = function(_, fname)
        return TPFile[fname]
      end
    }),
    system = TPSystem,
    web = TPWeb,
    user = TPUser,
    -- Expose the context itself for templates that use it directly
    ctx = ctx,
  }, { __index = _G })

  -- First, remove comment blocks: <%# ... %> and <%-- ... --%>
  local function remove_comments(str)
    local result = str
    local pos = 1
    local len = #result
    while pos <= len do
      local start_hash = result:find("<%#", pos, true)
      local start_dash = result:find("<%--", pos, true)

      local start_tag, end_pattern
      if start_hash and start_dash then
        if start_hash < start_dash then
          start_tag = start_hash
          end_pattern = "%>"
        else
          start_tag = start_dash
          end_pattern = "--%>"
        end
      elseif start_hash then
        start_tag = start_hash
        end_pattern = "%>"
      elseif start_dash then
        start_tag = start_dash
        end_pattern = "--%>"
      else
        break
      end

      local end_tag = result:find(end_pattern, start_tag + 3, true)
      if not end_tag then
        break
      end
      result = result:sub(1, start_tag - 1) .. result:sub(end_tag + #end_pattern)
      pos = start_tag
      len = #result
    end
    return result
  end

  local result = remove_comments(template)

  -- Single-pass processing: parse the template into a sequence of text, statements, and expressions
  -- Track trim markers on each part
  local parts = {} -- array of {type="text"|"stmt"|"expr", content=string, trim_leading=bool, trim_trailing=bool}
  pos = 1
  len = #result

  while pos <= len do
    local next_tag = result:find("<%", pos, true)
    if not next_tag then
      -- Remaining text
      if pos <= len then
        table.insert(parts, { type = "text", content = result:sub(pos), trim_leading = false, trim_trailing = false })
      end
      break
    end

    -- Text before tag
    if next_tag > pos then
      table.insert(parts, { type = "text", content = result:sub(pos, next_tag - 1), trim_leading = false, trim_trailing = false })
    end

    -- Check tag type
    local tag_start = next_tag
    local tag_char = result:sub(next_tag + 2, next_tag + 2)

    -- Detect trim markers
    local trim_leading = false
    local trim_trailing = false

    if result:sub(next_tag + 2, next_tag + 2) == "-" then
      trim_leading = true
      next_tag = next_tag + 1 -- Skip the '-'
      tag_char = result:sub(next_tag + 2, next_tag + 2)
    end

    if tag_char == "=" then
      -- Expression: <%= ... %> or <%-= ... %>
      local end_tag = result:find("%>", next_tag + 3, true)
      if not end_tag then
        table.insert(parts, { type = "text", content = result:sub(tag_start), trim_leading = false, trim_trailing = false })
        break
      end
      -- Check for trailing trim marker (single or double dash)
      local original_end_tag = end_tag
      if result:sub(end_tag - 1, end_tag - 1) == "-" then
        trim_trailing = true
        end_tag = end_tag - 1
        -- Check for double-dash trim marker (--%>)
        if result:sub(end_tag - 1, end_tag - 1) == "-" then
          end_tag = end_tag - 1
        end
      end
      local code = vim.trim(result:sub(next_tag + 3, end_tag - 1))
      table.insert(parts, { type = "expr", content = code, trim_leading = trim_leading, trim_trailing = trim_trailing })
      pos = original_end_tag + 2
    elseif tag_char == "#" or (tag_char == "-" and result:sub(next_tag + 3, next_tag + 3) == "-") then
      -- Comment: <%# ... %> or <%-- ... --%> (already removed, but handle just in case)
      local end_pattern = tag_char == "#" and "%>" or "--%>"
      local end_tag = result:find(end_pattern, next_tag + 3, true)
      if not end_tag then
        table.insert(parts, { type = "text", content = result:sub(tag_start), trim_leading = false, trim_trailing = false })
        break
      end
      pos = end_tag + #end_pattern
    else
      -- Statement: <% ... %> or <%- ... %>
      local end_tag = result:find("%>", next_tag + 2, true)
      if not end_tag then
        table.insert(parts, { type = "text", content = result:sub(tag_start), trim_leading = false, trim_trailing = false })
        break
      end
      -- Check for trailing trim marker (single or double dash)
      local original_end_tag = end_tag
      if result:sub(end_tag - 1, end_tag - 1) == "-" then
        trim_trailing = true
        end_tag = end_tag - 1
        -- Check for double-dash trim marker (--%>)
        if result:sub(end_tag - 1, end_tag - 1) == "-" then
          end_tag = end_tag - 1
        end
      end
      local code = result:sub(next_tag + 2, end_tag - 1)
      table.insert(parts, { type = "stmt", content = code, trim_leading = trim_leading, trim_trailing = trim_trailing })
      pos = original_end_tag + 2
    end
  end

  -- Post-process: apply trim markers by modifying adjacent text parts
  -- If a part has trim_leading, trim trailing whitespace (including newlines) from previous text part
  -- If a part has trim_trailing, trim leading whitespace (including newlines) from next text part
  for i, part in ipairs(parts) do
    if part.trim_leading and i > 1 then
      local prev = parts[i - 1]
      if prev.type == "text" then
        -- Trim trailing whitespace (including newlines)
        prev.content = prev.content:gsub("%s+$", "")
      end
    end
    if part.trim_trailing and i < #parts then
      local next = parts[i + 1]
      if next.type == "text" then
        -- Trim leading whitespace (including newlines)
        next.content = next.content:gsub("^%s+", "")
      end
    end
  end

  -- Generate a single Lua function that executes all parts in one scope
  -- This allows local variables to persist across statements and expressions
  local lua_parts = { "local _output = {}" }
  for _, part in ipairs(parts) do
    if part.type == "text" then
      -- Escape the text for Lua string
      local escaped = part.content:gsub("\\", "\\\\"):gsub('"', '\\"'):gsub("\n", "\\n"):gsub("\r", "\\r")
      table.insert(lua_parts, string.format('_output[#_output+1] = "%s"', escaped))
    elseif part.type == "stmt" then
      table.insert(lua_parts, part.content)
    elseif part.type == "expr" then
      table.insert(lua_parts, string.format('_output[#_output+1] = tostring(%s or "")', part.content))
    end
  end
  table.insert(lua_parts, "return table.concat(_output)")

  local combined_code = table.concat(lua_parts, "\n")
  local fn, err = load(combined_code, "templater_combined", "t", env)
  if not fn then
    log.warn("Templater compile error: %s", err)
    return template -- Return original on compile error
  end

  local ok, result = pcall(fn)
  if not ok then
    log.warn("Templater runtime error: %s", result)
    return template -- Return original on runtime error
  end

  return result
end

---Check if a template contains Templater syntax
---@param content string
---@return boolean
function M.has_templater_syntax(content)
  -- Check for Templater execution markers.
  if content:match "<%%" or content:match "<%=" or content:match "<%%#" then
    return true
  end

  -- Check for a leading ```js code block (within first 10 lines).
  local line_idx = 0
  for line in content:gmatch "[^\n]*\n?" do
    line_idx = line_idx + 1
    if line_idx > 10 then
      break
    end
    if line:match "^%s*```js%s*$" then
      return true
    end
  end

  return false
end

---Clear user scripts cache (call when config changes)
function M.clear_cache()
  user_scripts_cache = {}
end

return M