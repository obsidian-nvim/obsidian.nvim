local new_set, eq = MiniTest.new_set, MiniTest.expect.equality

local h = dofile "tests/helpers.lua"

local T, child = h.child_vault {
  pre_case = [[
    api = require "obsidian.api"
    log = require "obsidian.log"
    img = require "obsidian.img_paste"
    Path = require "obsidian.path"
  ]],
}

local test_cases = {
  {
    img_type = "png",
    confirm_img_paste = true,
    fname = "",
    user_input = nil,
    expected_name = nil,
    expected_msg = "Paste aborted",
  },
  {
    img_type = "png",
    confirm_img_paste = true,
    fname = "fname",
    user_input = "user input name",
    expected_name = "fname",
    expected_msg = nil,
  },
  {
    img_type = "png",
    confirm_img_paste = true,
    fname = "",
    user_input = "user input name",
    expected_name = "user input name",
    expected_msg = nil,
  },
  {
    img_type = nil,
    confirm_img_paste = true,
    fname = "",
    user_input = "user input name",
    expected_name = nil,
    expected_msg = "There is no image data in the clipboard",
  },
}

local parametrize_data = vim.tbl_map(function(case)
  return { case }
end, test_cases)

T["resolve_image_path"] = new_set { parametrize = parametrize_data }

T["resolve_image_path"]["Test based on user settings"] = function(case)
  -- Run the paste_img command in an isolated child process
  local results = child.lua(
    [[
    local case = ...

    -- Keep track of state to be analyzed by parent
    _G.captured_warn = nil
    _G.captured_err = nil
    _G.captured_paste_path = nil
    _G.captured_img_type = nil

    Obsidian.opts.attachments = {
      folder = "assets/imgs",
      img_name_func = function() return "img name func" end,
      confirm_img_paste = case.confirm_img_paste,
    }

    -- Mock functions called by obsidian.commands.paste_img
    log.warn = function(msg) _G.captured_warn = msg end
    log.err  = function(msg) _G.captured_err = msg end
    api.input = function() return case.user_input end

    img.get_clipboard_img_type = function() return case.img_type end

    img.paste = function(path, img_type)
      _G.captured_paste_path = tostring(path)
      _G.captured_img_type = img_type
    end

    -- Run Command
    local paste_img = require('obsidian.commands.paste_img')
    paste_img({ args = case.fname })

    -- Return the state to the parent
    return {
      warn = _G.captured_warn,
      err = _G.captured_err,
      paste_path = _G.captured_paste_path,
      img_type = _G.captured_img_type
    }
  ]],
    { case }
  )

  -- Check for warning or error messages if expected
  if case.expected_msg then
    local actual_msg = results.err or results.warn
    eq(case.expected_msg, actual_msg)
  -- Otherwise assume there was no warning or error
  else
    eq(nil, results.err)
    eq(nil, results.warn)
  end

  -- Check for path name if expected
  if case.expected_name then
    -- Reconstruct expected path based on child's vault root
    local vault_root = child.lua_get "Obsidian.dir.filename"
    local expected_path = string.format("%s/assets/imgs/%s", vault_root, case.expected_name)

    eq(expected_path, results.paste_path)
    eq(case.img_type, results.img_type)
  -- Otherwise assume no path will be set
  else
    eq(nil, results.paste_path)
  end
end

return T
