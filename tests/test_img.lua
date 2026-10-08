local eq = MiniTest.expect.equality
local new_set = MiniTest.new_set
local Path = require "obsidian.path"
local source = require "obsidian.img.source"
local original_load = source.load

local T = new_set {
  hooks = {
    post_case = function()
      source.load = original_load
    end,
  },
}

local function be32(n)
  return string.char(math.floor(n / 16777216) % 256, math.floor(n / 65536) % 256, math.floor(n / 256) % 256, n % 256)
end

local function png(width, height)
  return "\137PNG\r\n\26\n" .. be32(13) .. "IHDR" .. be32(width) .. be32(height) .. "\8\6\0\0\0\0\0\0\0"
end

local function write_binary(path, bytes)
  local file = assert(io.open(path, "wb"))
  file:write(bytes)
  file:close()
end

T["derives cell aspect ratio from terminal pixel dimensions"] = function()
  local img = require "obsidian.img"
  eq(1.5, img.cell_aspect_ratio { row = 24, col = 80, xpixel = 800, ypixel = 360 })
  eq(2, img.cell_aspect_ratio())
end

T["fits pixel dimensions using terminal cell aspect ratio"] = function()
  local img = require "obsidian.img"
  local width, height = img.fit(100, 100, 60, 20)
  eq(40, width)
  eq(20, height)

  width, height = img.fit(200, 100, 60, 20)
  eq(60, width)
  eq(15, height)
end

T["owns, updates, and idempotently deletes a fitted PNG"] = function()
  local img = require "obsidian.img"
  local path = Path.temp { suffix = ".png" }
  write_binary(tostring(path), png(800, 400))

  local calls = {}
  local deleted = {}
  local backend = {
    set = function(data_or_id, opts)
      calls[#calls + 1] = { data_or_id = data_or_id, opts = opts }
      return 41
    end,
    get = function() end,
    del = function(id)
      deleted[#deleted + 1] = id
      return true
    end,
  }
  local owner = img.owner { backend = backend }
  local completed
  local started = owner:show({
    source = tostring(path),
    placement = { row = 2, col = 3, max_width = 60, max_height = 20 },
  }, function(ok, err)
    completed = { ok, err }
  end)

  eq(true, started)
  eq(
    true,
    vim.wait(1000, function()
      return completed ~= nil
    end)
  )
  eq({ true }, completed)
  eq(1, #calls)
  eq("string", type(calls[1].data_or_id))
  eq(60, calls[1].opts.width)
  eq(15, calls[1].opts.height)
  eq(2, calls[1].opts.row)
  eq(nil, calls[1].opts.max_width)

  local updated = owner:update { row = 4, col = 5, width = 10, height = 5 }
  eq(true, updated)
  eq(2, #calls)
  eq(41, calls[2].data_or_id)
  eq(4, calls[2].opts.row)

  owner:close()
  owner:close()
  eq({ 41 }, deleted)
  vim.fn.delete(tostring(path))
end

T["ignores a stale load when a newer request wins"] = function()
  local img = require "obsidian.img"
  local calls = {}
  local owner = img.owner {
    backend = {
      set = function(_, opts)
        calls[#calls + 1] = opts
        return #calls
      end,
      get = function() end,
      del = function() end,
    },
  }

  owner:show {
    source = { bytes = png(100, 100) },
    placement = { max_width = 20, max_height = 20 },
  }
  owner:show {
    source = { bytes = png(200, 100) },
    placement = { max_width = 20, max_height = 20 },
  }

  eq(
    true,
    vim.wait(1000, function()
      return #calls == 1
    end)
  )
  eq(20, calls[1].width)
  eq(5, calls[1].height)
  owner:close()
end

T["cancels stale source callbacks after a new request"] = function()
  local img = require "obsidian.img"
  local pending = {}
  source.load = function(_, callback)
    pending[#pending + 1] = callback
  end
  local calls = 0
  local owner = img.owner {
    backend = {
      set = function()
        calls = calls + 1
        return calls
      end,
      get = function() end,
      del = function() end,
    },
  }
  owner:show { source = { bytes = png(1, 1) } }
  owner:show { source = { bytes = png(2, 2) } }
  pending[1] { bytes = png(1, 1), width = 1, height = 1 }
  eq(0, calls)
  pending[2] { bytes = png(2, 2), width = 2, height = 2 }
  eq(1, calls)
  owner:close()
end

T["reports unsupported and malformed sources without throwing"] = function()
  local img = require "obsidian.img"
  local unsupported
  local owner = img.owner { backend = {} }
  local started, err = owner:show({ source = { bytes = png(1, 1) } }, function(ok, message)
    unsupported = { ok, message }
  end)
  eq(false, started)
  eq("vim.ui.img is unavailable", err)
  eq(
    true,
    vim.wait(1000, function()
      return unsupported ~= nil
    end)
  )
  eq(false, unsupported[1])

  local malformed
  local valid_owner = img.owner {
    backend = {
      set = function()
        error "must not be called"
      end,
      get = function() end,
      del = function() end,
    },
  }
  valid_owner:show({ source = { bytes = "not png" } }, function(ok, message)
    malformed = { ok, message }
  end)
  eq(
    true,
    vim.wait(1000, function()
      return malformed ~= nil
    end)
  )
  eq(false, malformed[1])
  eq("truncated PNG", malformed[2])
  owner:close()
  valid_owner:close()
end

T["loads PNG files larger than the old byte limit"] = function()
  local path = Path.temp { suffix = ".png" }
  local bytes = png(1, 1) .. string.rep("x", 10 * 1024 * 1024)
  write_binary(tostring(path), bytes)
  local result, err
  source.load(tostring(path), function(value, load_err)
    result, err = value, load_err
  end)
  eq(
    true,
    vim.wait(2000, function()
      return result ~= nil or err ~= nil
    end)
  )
  eq(nil, err)
  eq(#bytes, #result.bytes)
  vim.fn.delete(tostring(path))
end

T["marked preview buffers work in any window and clean up on buffer change"] = function()
  local picker_util = require "obsidian.picker.util"
  local original_obsidian = Obsidian
  Obsidian = { opts = { img = { enabled = true } } }
  local path = Path.temp { suffix = ".png" }
  write_binary(tostring(path), png(16, 8))
  local spec = picker_util.preview_path(path)
  vim.bo[spec.buf].bufhidden = "hide"
  local other = vim.api.nvim_create_buf(false, true)
  local win = vim.api.nvim_open_win(other, false, { relative = "editor", row = 1, col = 1, width = 30, height = 10 })
  local old_backend = vim.ui.img
  local deleted = {}
  local created = 0
  vim.ui.img = {
    set = function(bytes_or_id)
      if type(bytes_or_id) ~= "number" then
        created = created + 1
      end
      return created
    end,
    get = function() end,
    del = function(id)
      deleted[#deleted + 1] = id
    end,
  }
  vim.api.nvim_win_set_buf(win, spec.buf)
  eq(
    true,
    vim.wait(1000, function()
      return created == 1 and vim.api.nvim_buf_get_lines(spec.buf, 0, 1, false)[1] == ""
    end)
  )
  vim.api.nvim_win_set_buf(win, other)
  eq({ 1 }, deleted)
  eq("Attachment Info", vim.api.nvim_buf_get_lines(spec.buf, 0, 1, false)[1])
  vim.api.nvim_win_close(win, true)
  vim.api.nvim_buf_delete(spec.buf, { force = true })
  vim.ui.img = old_backend
  Obsidian = original_obsidian
  vim.fn.delete(tostring(path))
end

T["picker path previews never put image bytes in a buffer"] = function()
  local picker_util = require "obsidian.picker.util"
  local path = Path.temp { suffix = ".PNG" }
  write_binary(tostring(path), png(16, 8) .. "\0binary")

  local spec = picker_util.preview_path(path)
  local lines = vim.api.nvim_buf_get_lines(spec.buf, 0, -1, false)
  eq("Attachment Info", lines[1])
  eq("PNG", lines[4]:match "PNG")
  eq(tostring(path), vim.api.nvim_buf_get_name(spec.buf))
  eq(false, table.concat(lines, "\n"):find "\0" ~= nil)

  vim.api.nvim_buf_delete(spec.buf, { force = true })
  vim.fn.delete(tostring(path))
end

return T
