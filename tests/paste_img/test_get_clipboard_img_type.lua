local M = require "obsidian.img_paste"
local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local api = require "obsidian.api"

local T = new_set()

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


local parametrize_data = vim.tbl_map(function(case) return { case } end, test_cases)

-- call test across all test cases
T["get_clipboard_img_type"] = new_set { parametrize = parametrize_data }

T["get_clipboard_img_type"]["should return correct image type for OS: {1}"] = function(case)

  -- Mock API to test against several different OS types
  api.get_os = function()
    return case.os_type
  end
  
  -- Mock display server
  os.getenv = function(var)
    if var == "XDG_SESSION_TYPE" then
      return case.display_server
    end
    return original_os_getenv(var)
  end

  -- Mock command needed to output data
  vim.fn.system = function(cmd)
    eq(case.expected_cmd, cmd, "The wrong system command was called.")
    return case.mock_output
  end

  -- Run get_clipbaord_img_type with mocked functions
  local img_type = M.get_clipboard_img_type()

  eq(case.expected_img_type, img_type)
end

return T
