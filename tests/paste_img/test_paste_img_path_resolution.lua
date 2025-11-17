local M = require "obsidian.commands.paste_img"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local api = require "obsidian.api"
local log = require "obsidian.log"
local img = require "obsidian.img_paste"
local Path = require "obsidian.path"


local test_cases = {
  {
    img_type = "png",
    confirm_img_paste = true,
    fname = "",
    user_input = nil,
    expected_name = nil,
    expected_msg = "Paste aborted"
  },
  {
    img_type = "png",
    confirm_img_paste = true,
    fname = "fname",
    user_input = "user input name",
    expected_name = "fname",
    expected_msg = nil
  },
  {
    img_type = "png",
    confirm_img_paste = true,
    fname = "",
    user_input = "user input name",
    expected_name = "user input name",
    expected_msg = nil
  },
  {
    img_type = nil,
    confirm_img_paste = true,
    fname = "",
    user_input = "user input name",
    expected_name = "user input name",
    expected_msg = "There is no image data in the clipboard"
  },
}

local parametrize_data = vim.tbl_map(function(case) return { case } end, test_cases)

local T = new_set()

T["resolve_image_path"] = new_set{ parametrize = parametrize_data }

T["resolve_image_path"]["Test based on user settings"] = function(case)
    img.get_clipboard_img_type = function()
        return case.img_type 
    end

    log.warn = function(msg, ...)
        eq(case.expected_msg, msg)
    end

    log.err = function(msg, ...)
        eq(case.expected_msg, msg)
    end

    Obsidian.opts.attachments = {
      img_folder = "assets/imgs",
      img_name_func = function()
        return "img name func" 
      end,
      confirm_img_paste = case.confirm_img_paste,
    }

    api.input = function(prompt, opts) return case.user_input end

    img.paste = function(path, img_type)
      local vault_root = Path.new(Obsidian.dir.filename)
      expected_path = tostring(vault_root / "assets/imgs" / case.expected_name)

      eq(expected_path, path)
      eq("png", img_type)
    end

    M({ args = case.fname })

end

return T
