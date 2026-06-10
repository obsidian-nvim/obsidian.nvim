local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local api = require "obsidian.api"

local T = new_set()

T["bare_url"] = function()
  eq("https://example.com/a", api.bare_url "  https://example.com/a\n")
  eq("http://example.com", api.bare_url "http://example.com")
  eq(nil, api.bare_url "not a url")
  eq(nil, api.bare_url "see https://example.com please")
  eq(nil, api.bare_url(nil))
end

---Run fn with obsidian.clipboard replaced by a stub.
---@param stub table
---@param fn fun()
local function with_clipboard(stub, fn)
  local real = package.loaded["obsidian.clipboard"]
  package.loaded["obsidian.clipboard"] = stub
  local ok, err = pcall(fn)
  package.loaded["obsidian.clipboard"] = real
  assert(ok, err)
end

local function scratch_buf()
  local buf = vim.api.nvim_create_buf(false, true)
  vim.api.nvim_set_current_buf(buf)
  return buf
end

local function buf_lines(buf)
  return vim.api.nvim_buf_get_lines(buf, 0, -1, false)
end

T["paste"] = new_set()

T["paste"]["pastes plain text from the clipboard"] = function()
  with_clipboard({
    has_html = function()
      return false
    end,
    get_text = function()
      return "plain text"
    end,
  }, function()
    local buf = scratch_buf()
    api.paste()
    eq({ "plain text" }, buf_lines(buf))
  end)
end

T["paste"]["pastes a bare url raw"] = function()
  with_clipboard({
    has_html = function()
      return false
    end,
    get_text = function()
      return "https://example.com/a\n"
    end,
  }, function()
    local buf = scratch_buf()
    api.paste { url_as = "raw" }
    eq({ "https://example.com/a" }, buf_lines(buf))
  end)
end

T["paste"]["pastes an image through general paste"] = function()
  with_clipboard({
    has_html = function()
      return false
    end,
    get_text = function()
      return nil
    end,
  }, function()
    local real_get_os = api.get_os
    local real_system = vim.system
    local real_obsidian = rawget(_G, "Obsidian")

    local ok, err = pcall(function()
      _G.Obsidian = {
        opts = {
          attachments = {
            confirm_img_paste = false,
            img_text_func = require("obsidian.builtin").img_text_func,
          },
          link = { style = "wiki" },
        },
      }
      api.get_os = function()
        return api.OSType.Darwin
      end
      vim.system = function(cmd)
        eq({ "pngpaste", "meow.png" }, cmd)
        return { wait = function() end }
      end

      local buf = scratch_buf()
      api.paste { kind = "image", path = "meow", img_type = "png" }
      eq({ "![[meow.png]]" }, buf_lines(buf))
    end)

    api.get_os = real_get_os
    vim.system = real_system
    _G.Obsidian = real_obsidian
    assert(ok, err)
  end)
end

if vim.fn.executable "pandoc" == 1 then
  T["paste"]["inserts at the recorded position even if the cursor moves"] = function()
    with_clipboard({
      has_html = function()
        return true
      end,
      get_html = function()
        return "<em>late</em>"
      end,
      get_text = function()
        return "late"
      end,
    }, function()
      local buf = scratch_buf()
      vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "first", "second" })
      vim.api.nvim_win_set_cursor(0, { 1, 4 }) -- on the 't' of "first"

      api.paste { backend = "pandoc" }

      -- move away while the conversion is in flight
      vim.api.nvim_win_set_cursor(0, { 2, 3 })

      local ok = vim.wait(10000, function()
        return vim.deep_equal({ "first*late*", "second" }, buf_lines(buf))
      end, 10)
      eq(true, ok)
      -- the cursor was not yanked back to the paste position
      eq({ 2, 3 }, vim.api.nvim_win_get_cursor(0))
    end)
  end

  T["paste"]["converts clipboard html to markdown"] = function()
    with_clipboard({
      has_html = function()
        return true
      end,
      get_html = function()
        return "<p>hello <strong>world</strong></p>"
      end,
      get_text = function()
        return "hello world"
      end,
    }, function()
      local buf = scratch_buf()
      api.paste { backend = "pandoc" }
      local ok = vim.wait(10000, function()
        return vim.deep_equal({ "hello **world**" }, buf_lines(buf))
      end, 10)
      eq(true, ok)
    end)
  end
end

T["attach"] = new_set()

T["attach"]["converts multiline clipboard html"] = function()
  local real_vim_paste = vim.paste
  local real_clipboard = package.loaded["obsidian.clipboard"]
  local real_html = package.loaded["obsidian.html"]
  local real_paste = package.loaded["obsidian.paste"]
  local real_auto_paste = vim.g.obsidian_auto_paste

  local ok, err = pcall(function()
    package.loaded["obsidian.clipboard"] = {
      has_html = function()
        return true
      end,
      get_html = function()
        return "<p>hello</p><p>world</p>"
      end,
      get_text = function()
        return "hello\nworld"
      end,
    }
    package.loaded["obsidian.html"] = {
      to_markdown_async = function(_, _, callback)
        callback "hello\nworld"
      end,
    }
    package.loaded["obsidian.paste"] = nil

    local buf = scratch_buf()
    vim.api.nvim_buf_set_lines(buf, 0, -1, false, { "anchor" })
    vim.api.nvim_win_set_cursor(0, { 1, 0 })
    vim.b.obsidian_buffer = true

    local overridden_called = false
    vim.paste = function()
      overridden_called = true
      return true
    end

    require("obsidian.paste").attach(buf)
    eq(true, vim.paste({ "hello", "world" }, -1))

    local converted = vim.wait(1000, function()
      return vim.deep_equal({ "anchor", "hello", "world" }, buf_lines(buf))
    end, 10)
    eq(true, converted)
    eq(false, overridden_called)
  end)

  vim.paste = real_vim_paste
  package.loaded["obsidian.clipboard"] = real_clipboard
  package.loaded["obsidian.html"] = real_html
  package.loaded["obsidian.paste"] = real_paste
  vim.g.obsidian_auto_paste = real_auto_paste
  vim.b.obsidian_buffer = nil

  assert(ok, err)
end

return T
