local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local api = require "obsidian.api"

local T, child = h.child_vault {
  pre_case = [[api = require"obsidian.api"]],
}

local test_cases = {
  {
    name = "Darwin with a png",
    os_type = api.OSType.Darwin,
    expected_cmd = "pngpaste -b 2>&1",
    mock_output = "iVBORw0KG-fake-base64-data",
    expected_img_type = "png",
  },
  {
    name = "Windows with a png",
    os_type = api.OSType.Windows,
    expected_cmd = 'powershell.exe "Get-Clipboard -Format Image"',
    mock_output = "Some clipboard content\n",
    expected_img_type = "png",
  },
  {
    name = "Linux (Wayland) with a png",
    os_type = api.OSType.Linux,
    display_server = "wayland",
    expected_cmd = "wl-paste --list-types",
    mock_output = "image/png\ntext/plain",
    expected_img_type = "png",
  },
  {
    name = "Linux (X11) with a jpeg",
    os_type = api.OSType.Linux,
    display_server = "x11",
    expected_cmd = "xclip -selection clipboard -o -t TARGETS",
    mock_output = "image/jpeg\napplication/pdf",
    expected_img_type = "jpeg",
  },
  {
    name = "WSL with a png",
    os_type = api.OSType.Wsl,
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
      api.get_os = function()
        return case.os_type
      end

      os.getenv = function(var)
        if var == "XDG_SESSION_TYPE" then
          return case.display_server
        end
        return api.get_os()
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

return T
