local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local platform = require "obsidian.platform"

local T, child = h.child_vault {
  pre_case = [[platform = require "obsidian.platform"]],
}

local test_cases = {
  {
    name = "Darwin with a png",
    os_type = platform.OSType.Darwin,
    expected_cmd = "pngpaste -b 2>&1",
    mock_output = "iVBORw0KG-fake-base64-data",
    expected_img_type = "png",
  },
  {
    name = "Windows with a png",
    os_type = platform.OSType.Windows,
    expected_cmd = 'powershell.exe "Get-Clipboard -Format Image"',
    mock_output = "Some clipboard content\n",
    expected_img_type = "png",
  },
  {
    name = "Linux (Wayland) with a png",
    os_type = platform.OSType.Linux,
    display_server = "wayland",
    expected_cmd = "wl-paste --list-types",
    mock_output = "image/png\ntext/plain",
    expected_img_type = "png",
  },
  {
    name = "Linux (X11) with a jpeg",
    os_type = platform.OSType.Linux,
    display_server = "x11",
    expected_cmd = "xclip -selection clipboard -o -t TARGETS",
    mock_output = "image/jpeg\napplication/pdf",
    expected_img_type = "jpeg",
  },
  {
    name = "WSL with a png",
    os_type = platform.OSType.Wsl,
    expected_cmd = 'powershell.exe "Get-Clipboard -Format Image"',
    mock_output = "Some clipboard content\n",
    expected_img_type = "png",
  },
}

local parametrize_data = vim.tbl_map(function(case)
  return { case }
end, test_cases)

T["get_clipboard_img_type"] = new_set { parametrize = parametrize_data }

T["get_clipboard_img_type"]["should return correct image type for OS"] = function(case)
  -- Set up mocked functions to test get_clipboard_img_type
  child.lua(
    [[
      local case = ...  
      platform.get_os = function()
        return case.os_type
      end

      os.getenv = function(var)
        if var == "XDG_SESSION_TYPE" then
          return case.display_server
        end
        return platform.get_os()
      end

      vim.fn.executable = function()
        return 1
      end

      vim.fn.system = function(cmd)
        assert(case.expected_cmd, cmd, "The wrong system command was called.")
        return case.mock_output
      end
  ]],
    { case }
  )

  -- Run get_clipboard_img_type
  local result = child.lua_get [[require('obsidian.img_paste').get_clipboard_img_type()]]

  eq(case.expected_img_type, result)
end

T["get_clipboard_img_type"]["reports a missing clipboard tool instead of an empty clipboard"] = function(case)
  child.lua(
    [[
      local case = ...
      platform.get_os = function()
        return case.os_type
      end

      os.getenv = function(var)
        if var == "XDG_SESSION_TYPE" then
          return case.display_server
        end
        return platform.get_os()
      end

      vim.fn.executable = function()
        return 0
      end

      _G.system_called = false
      vim.fn.system = function()
        _G.system_called = true
        return case.mock_output
      end
  ]],
    { case }
  )

  local result = child.lua [[
    local img_type, err = require("obsidian.img_paste").get_clipboard_img_type()
    return { found = img_type ~= nil, err = err }
  ]]
  local tool = case.expected_cmd:match "^%S+"

  eq(false, result.found)
  eq(string.format("`%s` was not found in PATH; it is needed to read images from the clipboard", tool), result.err)
  eq(false, child.lua_get "_G.system_called")
end

return T
