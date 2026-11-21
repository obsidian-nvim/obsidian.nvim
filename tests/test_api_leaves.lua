local eq = MiniTest.expect.equality
local child = MiniTest.new_child_neovim()
local T = MiniTest.new_set {
  hooks = {
    pre_case = function()
      child.restart { "-u", "NONE", "--noplugin" }
      child.lua [[vim.opt.rtp:prepend(vim.uv.cwd())]]
    end,
    post_case = child.stop,
  },
}

T["leaf imports and an ordinary path check do not require setup"] = function()
  eq(
    {},
    child.lua [[
    require "obsidian.platform"
    require "obsidian.runtime"
    require "obsidian.editor.prompt"
    local Path = require "obsidian.path"
    assert(not Path.new("relative.md"):is_absolute())
    assert(_G.Obsidian == nil)
    local loaded = {}
    for _, name in ipairs({ "obsidian", "obsidian.api", "obsidian.actions", "obsidian.note", "obsidian.picker", "obsidian.ui" }) do
      if package.loaded[name] then
        loaded[#loaded + 1] = name
      end
    end
    for name in pairs(package.loaded) do
      if name:match("^obsidian%.lsp") then
        loaded[#loaded + 1] = name
      end
    end
    return loaded
  ]]
  )
end

T["legacy API and root access still expose the extracted helpers"] = function()
  eq(
    true,
    child.lua [[
    local api = require "obsidian.api"
    local platform = require "obsidian.platform"
    local runtime = require "obsidian.runtime"
    local prompt = require "obsidian.editor.prompt"
    local attachment = require "obsidian.attachment"
    return require("obsidian").api == api
      and api.input == prompt.input and api.confirm == prompt.confirm
      and api.get_os == platform.get_os and api.OSType == platform.OSType
      and api.get_plugin_info == runtime.get_plugin_info and api.docs_dir == runtime.docs_dir
      and api.dir == require("obsidian.fs").dir
      and api.resolve_attachment_path == attachment.destination_path
      and api.resolve_image_path == attachment.destination_path
      and api.is_attachment_path == attachment.is_attachment_path
  ]]
  )
end

T["prompts distinguish cancelled input from an empty answer and preserve choice labels"] = function()
  eq(
    { "note name", "", true, "No", "Yes with Template", true },
    child.lua [[
    local prompt = require "obsidian.editor.prompt"
    vim.fn.input = function(opts)
      assert(opts.prompt == "Name: ")
      if opts.default then
        assert(opts.completion == "file")
        return "  " .. opts.default .. " "
      end
      return "   "
    end
    local name = prompt.input("Name", { default = "note name", completion = "file" })
    local empty = prompt.input "Name: "
    vim.fn.input = function(opts) return opts.cancelreturn end
    local cancelled = prompt.input "Name" == nil
    assert(select("#", prompt.input "Name") == 1)

    vim.fn.confirm = function(message, choices)
      assert(message == "Proceed?")
      assert(choices == "&Yes\n&No" or choices == "&Yes\nYes with &Template\n&No")
      return 2
    end
    local default_label = prompt.confirm "Proceed?"
    local custom_label = prompt.confirm("Proceed?", "&Yes\nYes with &Template\n&No")
    vim.fn.confirm = function() return 0 end
    assert(select("#", prompt.confirm "Proceed?") == 1)
    return { name, empty, cancelled, default_label, custom_label, prompt.confirm("Proceed?") == nil }
  ]]
  )
end

T["runtime discovery preserves path, Git metadata and unknown-revision fallback"] = function()
  eq(
    { "abc123", "unknown", true },
    child.lua [[
    local runtime = require "obsidian.runtime"
    local path = vim.fs.joinpath(vim.fn.tempname(), "obsidian.nvim")
    vim.api.nvim_list_runtime_paths = function() return { path, path .. "-other" } end
    local calls = 0
    vim.system = function(cmd, opts)
      calls = calls + 1
      assert(vim.deep_equal(cmd, { "git", "rev-parse", "HEAD" }))
      assert(opts.cwd == path)
      return { wait = function(_, timeout)
        assert(timeout == 1000)
        return calls == 1 and { code = 0, stdout = "abc123\n" } or { code = 1 }
      end }
    end
    assert(runtime.get_plugin_info("missing") == nil and calls == 0)
    local info = runtime.get_plugin_info "obsidian.nvim"
    assert(info.path == path)
    local unknown = runtime.get_plugin_info "obsidian.nvim"
    return { info.commit, unknown.commit, tostring(runtime.docs_dir()) == vim.fs.normalize(vim.fs.joinpath(path, "docs")) }
  ]]
  )
end

T["platform classifies WSL and reuses the result"] = function()
  eq(
    { "Wsl", "Wsl", 1 },
    child.lua [[
    local platform = require "obsidian.platform"
    local has = vim.fn.has
    vim.fn.has = function(feature)
      return feature == "win32" and 0 or has(feature)
    end
    local calls = 0
    vim.uv.os_uname = function()
      calls = calls + 1
      return { sysname = "Linux", release = "microsoft-standard-WSL2" }
    end
    return { platform.get_os(), platform.get_os(), calls }
  ]]
  )
end

return T
