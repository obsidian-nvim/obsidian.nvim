local h = dofile "tests/helpers.lua"
local T, child = h.child_vault()
local eq = MiniTest.expect.equality

local function open_note(contents)
  local files = h.mock_vault_contents(child.Obsidian.dir, { ["note.md"] = contents })
  child.cmd("edit " .. vim.fn.fnameescape(files["note.md"]))
  child.lua [[vim.b.obsidian_buffer = true]]
end

local function download(new_name)
  return child.lua(([=[
    local attachment = require "obsidian.attachment"
    local captured
    attachment.add = function(url, opts)
      captured = { url = url, opts = opts }
      return "/vault/attachments/download.png"
    end
    attachment.format_link = function()
      return "![[download.png]]"
    end
    local result = require("obsidian.actions").download_url_attachment { new_name = %s }
    return { result = result, captured = captured }
  ]=]):format(vim.inspect(new_name)))
end

T["replaces an external Markdown link"] = function()
  open_note "See [image](https://example.com/image.png) now"
  child.api.nvim_win_set_cursor(0, { 1, 20 })

  local result = download "renamed.png"

  eq("See ![[download.png]] now", child.api.nvim_get_current_line())
  eq("https://example.com/image.png", result.captured.url)
  eq(false, result.captured.opts.insert)
  eq("renamed.png", result.captured.opts.new_name)
  eq("actions.download_url_attachment", result.captured.opts.scope)
  eq("/vault/attachments/download.png", result.result)
end

T["replaces a raw URL"] = function()
  open_note "Get https://example.com/file.png now"
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  download()

  eq("Get ![[download.png]] now", child.api.nvim_get_current_line())
end

T["replaces a Markdown autolink without leaving brackets"] = function()
  open_note "See <https://example.com/file.png> now"
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  download()

  eq("See ![[download.png]] now", child.api.nvim_get_current_line())
end

T["ignores URLs in code"] = function()
  open_note "`https://example.com/inline.png`\n```\nhttps://example.com/fenced.png\n```"

  child.api.nvim_win_set_cursor(0, { 1, 10 })
  eq(vim.NIL, child.lua [[return require("obsidian.actions")._cursor_url()]])

  child.api.nvim_win_set_cursor(0, { 3, 10 })
  eq(vim.NIL, child.lua [[return require("obsidian.actions")._cursor_url()]])
end

T["leaves text unchanged when download fails"] = function()
  open_note "https://example.com/fail.png"
  child.api.nvim_win_set_cursor(0, { 1, 10 })

  child.lua [[
    require("obsidian.attachment").add = function()
      return nil
    end
    require("obsidian.actions").download_url_attachment()
  ]]

  eq("https://example.com/fail.png", child.api.nvim_get_current_line())
end

return T
