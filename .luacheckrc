-- Re-run tests only if their modification time changed.
cache = true
std = luajit
codes = true
self = false

include_files = {
  "lua/obsidian/*",
  "tests/*",
}

exclude_files = {
  "_neovim/*",
  "_runtime/*",
  "deps/*",
  "tests/fixtures",
}

-- Glorious list of warnings: https://luacheck.readthedocs.io/en/stable/warnings.html
ignore = {
  "212", -- Unused argument, In the case of callback function, _arg_name is easier to understand than _, so this option is set to off.
  "122", -- Indirectly setting a readonly global
  "631", -- Line too long
}

-- Global objects defined by the C code
read_globals = {
  "Obsidian",
  "vim",
  "MiniDoc",
  "MiniTest",
  "it",
  "describe",
  "before_each",
  "after_each",
}
