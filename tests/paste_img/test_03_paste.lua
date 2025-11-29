local new_set, eq = MiniTest.new_set, MiniTest.expect.equality
local h = dofile "tests/helpers.lua"
local api = require "obsidian.api"

local T, child = h.child_vault {
  pre_case = [[
    api = require "obsidian.api"
    log = require "obsidian.log"
    img = require "obsidian.img_paste"
    Path = require "obsidian.path"
    util = require "obsidian.util"
  ]],
}

local test_cases = {
  {
    img_type = "png",
    file_name = "meow.png",
    expected_msg = "Paste aborted",
    os_type = api.OSType.Linux,
    display_server = "wayland",
    expected_cmd = nil,
    api_confirm = nil,
    confirm_img_paste = true,
  },
  {
    img_type = "png",
    file_name = "me^ow.png",
    expected_msg = "Links will not work with file names containing any of these characters in Obsidian: # ^ [ ] |",
    os_type = api.OSType.Linux,
    display_server = "wayland",
    expected_cmd = { "bash", "-c", "wl-paste --no-newline --type image/png > 'me^ow.png'" },
    confirm_img_paste = false,
  },
  {
    img_type = "jpeg",
    file_name = "meow.jpeg",
    expected_msg = nil,
    os_type = api.OSType.Linux,
    display_server = "x11",
    expected_cmd = { "bash", "-c", "xclip -selection clipboard -t image/jpeg -o > 'meow.jpeg'" },
    confirm_img_paste = false,
  },
  {
    img_type = "png",
    file_name = "meow.png",
    expected_msg = nil,
    os_type = api.OSType.Darwin,
    display_server = nil,
    expected_cmd = { "pngpaste", "meow.png" },
    confirm_img_paste = false,
  },
  {
    img_type = "png",
    file_name = "meow.png",
    expected_msg = nil,
    os_type = api.OSType.Windows,
    display_server = nil,
    expected_cmd = "powershell.exe -c \"(get-clipboard -format image).save('meow.png', 'png')\"",
    confirm_img_paste = false,
  },
  {
    img_type = "png",
    file_name = "meow.jpeg",
    expected_msg = "invalid suffix for image name '%s', must be '%s'",
    os_type = api.OSType.Darwin,
    display_server = nil,
    expected_cmd = nil,
    confirm_img_paste = false,
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

    local async = require("obsidian.async")

    Obsidian.opts.attachments = {
      img_folder = "assets/imgs",
      img_name_func = function() return "img name func" end,
      img_text_func = require("obsidian.builtin").img_text_func,
      confirm_img_paste = case.confirm_img_paste,
    }

    local vault_root = Obsidian.dir.filename
    local path_name = string.format("%s/assets/imgs/%s", vault_root, case.file_name)

    -- Keep track of state to be analyzed by parent
    _G.captured_warn = nil
    _G.captured_err = nil
    _G.captured_cmd = nil

    -- Mock functions called by obsidian.paste
    log.warn = function(msg) _G.captured_warn = msg end
    log.err  = function(msg) _G.captured_err = msg end
    api.confirm = function() return nil end

    -- Mock functions called by local function save_clipboard_image
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

    -- Used by Windows to run save clipboard image command
    os.execute = function(cmds)
        _G.captured_cmd = cmds
        return 0
    end

    -- Used by Linux & MacOS to run save clipboard image command
    async.run_job = function(cmds)
        _G.captured_cmd = cmds
        return 0
    end

    vim.api.nvim_put = function() end

    -- Reload package to utilize mocked run_job
    package.loaded["obsidian.img_paste"] = nil
    local img = require("obsidian.img_paste")

    -- Run Command
    img.paste(case.file_name, case.img_type)

    -- Return the state to the parent
    return {
      warn = _G.captured_warn,
      err = _G.captured_err,
      captured_cmd = _G.captured_cmd,
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

  eq(case.expected_cmd, results.captured_cmd)
end

return T
