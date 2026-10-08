local eq = MiniTest.expect.equality
local new_set = MiniTest.new_set
local Path = require "obsidian.path"

local T = new_set {
  hooks = {
    post_case = function()
      require("obsidian.img").clear_all()
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
    source = { path = tostring(path) },
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
  eq(40, calls[1].opts.width)
  eq(20, calls[1].opts.height)
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
  eq(10, calls[1].height)
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
end

T["picker path previews never put image bytes in a buffer"] = function()
  local picker_util = require "obsidian.picker.util"
  local path = Path.temp { suffix = ".PNG" }
  write_binary(tostring(path), png(16, 8) .. "\0binary")

  local spec = picker_util.preview_path(path)
  local lines = vim.api.nvim_buf_get_lines(spec.buf, 0, -1, false)
  eq("Native PNG preview", lines[1])
  eq("PNG", lines[4]:match "PNG")
  eq(tostring(path), spec.img.source.path)
  eq(false, table.concat(lines, "\n"):find "\0" ~= nil)

  vim.api.nvim_buf_delete(spec.buf, { force = true })
  vim.fn.delete(tostring(path))
end

return T
