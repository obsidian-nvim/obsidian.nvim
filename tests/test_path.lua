local Path = require "obsidian.path"
local api = require "obsidian.api"

local new_set, eq, has_error = MiniTest.new_set, MiniTest.expect.equality, MiniTest.expect.error

local T = new_set()

T["new"] = new_set()

T["new"]["should initialize with both method syntax and regular dot access"] = function()
  ---@type obsidian.Path
  local path

  path = Path.new "README.md"
  eq("README.md", path.filename)

  path = Path:new "README.md"
  eq("README.md", path.filename)
end

T["new"]["should return same object when arg is already a path"] = function()
  local path = Path.new "README.md"
  eq(path, Path.new(path))
end

T["new"]["should init from a plenary path"] = function()
  local PlenaryPath = require "plenary.path"
  local path = Path.new "README.md"
  eq(true, path == Path.new(PlenaryPath:new "README.md"))
end

T["new"]["should raise an error if 2 args are passed and the first isn't Path"] = function()
  has_error(function()
    ---@diagnostic disable-next-line
    Path.new(1, "bar")
  end)
end

if api.get_os() == api.OSType.Windows then
  T["new"]["should normalize lowercase c drives on windows correctly"] = function()
    local path = Path:new "c:/foo/bar"
    eq(path.filename, "C:/foo/bar")
  end
end

T["is_path_obj"] = new_set()

T["is_path_obj"]["should return true for obsidian.Path objects"] = function()
  local path = Path.new "README.md"
  eq(true, Path.is_path_obj(path))
end

T["is_path_obj"]["should return false for all other kinds of objects"] = function()
  eq(false, Path.is_path_obj(1))
  eq(false, Path.is_path_obj { a = 2 })
  eq(false, Path.is_path_obj(nil))
end

T["__eq"] = new_set()

T["__eq"]["should compare with other paths correctly"] = function()
  eq(true, Path:new "README.md" == Path:new "README.md")
  eq(true, Path:new "/foo" == Path:new "/foo/")

  local path = Path:new "README.md"
  local _ = path.name
  eq(true, path == Path:new "README.md")
  eq(true, path == Path.new(path))
end

T["__div"] = new_set()

T["__div"]["should join paths"] = function()
  assert(Path:new "/foo/" / "bar" == Path:new "/foo/bar")
end

T["name"] = new_set()

T["name"]["should return final component"] = function()
  eq("bar.md", Path:new("/foo/bar.md").name)
end

T["suffix"] = new_set()

T["suffix"]["should return final suffix"] = function()
  eq(".md", Path:new("/foo/bar.md").suffix)
  eq(".gz", Path:new("/foo/bar.tar.gz").suffix)
end

T["suffix"]["should return nil when there is no suffix"] = function()
  eq(nil, Path:new("/foo/bar").suffix)
end

T["suffixes"] = new_set()
T["suffixes"]["should return all extensions"] = function()
  eq({ ".md" }, Path:new("/foo/bar.md").suffixes)
  eq({ ".tar", ".gz" }, Path:new("/foo/bar.tar.gz").suffixes)
end

T["suffixes"]["should return empty list when there is no suffix"] = function()
  eq({}, Path:new("/foo/bar").suffixes)
end

T["stem"] = new_set()

T["stem"]["should return the final name without suffix"] = function()
  eq("bar", Path:new("/foo/bar.md").stem)
  eq(nil, Path:new("/").stem)
end

T["with_suffix"] = new_set()

T["with_suffix"]["should create a new path with the new suffix"] = function()
  eq(true, Path:new("/foo/bar.md"):with_suffix ".tar.gz" == Path.new "/foo/bar.tar.gz")
  eq(true, Path:new("/foo/bar.tar.gz"):with_suffix ".bz2" == Path.new "/foo/bar.tar.bz2")
  eq(true, Path:new("/foo/bar"):with_suffix ".md" == Path.new "/foo/bar.md")
end

T["with_suffix"]["should not add anything else to the filename"] = function()
  eq(Path.new "foo-bar.png", Path.new("foo-bar"):with_suffix ".png")
end

T["with_suffix"]["should fail when there is no stem"] = function()
  has_error(function()
    Path.new("/"):with_suffix ".png"
  end)
end

T["with_suffix"]["should allow appending the suffix instead of replacing it"] = function()
  eq(Path.new "johnny.md", Path.new("johnny.decimal"):with_suffix ".md")
  eq(Path.new "johnny.decimal.md", Path.new("johnny.decimal"):with_suffix(".md", true))
end

T["is_absolute"] = new_set()

T["is_absolute"]["should work for windows or unix paths"] = function()
  assert(Path:new("/foo/"):is_absolute())
  if api.get_os() == api.OSType.Windows then
    assert(Path:new("C:/foo/"):is_absolute())
    assert(Path:new("C:\\foo\\"):is_absolute())
  end
end

T["joinpath"] = new_set()
T["joinpath"]["can join multiple"] = function()
  eq(true, Path.new "foo/bar/baz.md" == Path.new("foo"):joinpath("bar", "baz.md"))
  eq(true, Path.new "foo/bar/baz.md" == Path.new("foo/"):joinpath("bar/", "baz.md"))
  eq(true, Path.new "foo/bar/baz.md" == Path.new("foo/"):joinpath("bar/", "/baz.md"))
end

T["relative_to"] = new_set()

T["relative_to"]["should work on absolute paths"] = function()
  eq("baz.md", Path:new("/foo/bar/baz.md"):relative_to("/foo/bar/").filename)
  eq("baz.md", Path:new("/foo/bar/baz.md"):relative_to("/foo/bar").filename)
  eq("baz.md", Path:new("/baz.md"):relative_to("/").filename)
end

T["relative_to"]["should raise an error when the relative path can't be resolved"] = function()
  has_error(function()
    Path:new("/bar/bar/baz.md"):relative_to "/foo/"
  end)

  has_error(function()
    Path:new("bar/bar/baz.md"):relative_to "/bar"
  end)
end

T["relative_to"]["should work on relative paths"] = function()
  eq("img.png", Path:new("assets/img.png"):relative_to("assets").filename)
  eq("img.png", Path:new("assets/img.png"):relative_to("./assets").filename)

  eq("assets/img.png", Path:new("assets/img.png"):relative_to("./").filename)
  eq("assets/img.png", Path:new("./assets/img.png"):relative_to("./").filename)
end

T["parent"] = new_set()

T["parent"]["should get the parent of the current"] = function()
  eq(Path.new("/foo/bar/README.md"):parent(), Path.new "/foo/bar")
end

T["parent"]["should return './' for an unresolved name to match Python pathlib API"] = function()
  eq(Path.new "./", Path.new("foo-bar"):parent())
end

T["parent"]["should return '/' for '/' to match Python pathlib API"] = function()
  eq(Path.new "/", Path.new("/"):parent())
end

T["parents"] = new_set()

T["parents"]["should collect all logical parents"] = function()
  eq(Path.new("/foo/bar/README.md"):parents(), { Path.new "/foo/bar", Path.new "/foo", Path.new "/" })
end

T["resolve"] = new_set()

T["resolve"]["should always resolve to the absolute path when it exists"] = function()
  eq(vim.fs.normalize(assert(vim.uv.fs_realpath "README.md")), Path.new("README.md"):resolve().filename)
end

T["resolve"]["should always resolve to an absolute path if a parent exists"] = function()
  eq(vim.fs.normalize(assert(vim.uv.fs_realpath ".")) .. "/tmp/dne.md", Path.new("tmp/dne.md"):resolve().filename)

  eq(vim.fs.normalize(assert(vim.uv.fs_realpath ".")) .. "/dne.md", Path.new("dne.md"):resolve().filename)
end

T["exists"] = new_set()

T["exists"]["should return true when the path exists"] = function()
  eq(true, Path.new("README.md"):exists())
  eq(true, Path.new("lua"):exists())
end

T["exists"]["should return false when the path does not exists"] = function()
  eq(false, Path.new("dne.md"):exists())
end

T["is_file"] = new_set()

T["is_file"]["should return true when the path is a file"] = function()
  eq(true, Path.new("README.md"):is_file())
  eq(false, Path.new("README.md"):is_dir())
end

T["is_file"]["should return false when the path is a directory"] = function()
  eq(false, Path.new("lua"):is_file())
end

T["is_dir"] = new_set()

T["is_dir"]["should return true when the path is a directory"] = function()
  eq(true, Path.new("lua"):is_dir())
  eq(false, Path.new("lua"):is_file())
end

T["is_dir"]["should return false when the path is a file"] = function()
  eq(false, Path.new("README.md"):is_dir())
end

T["is_dir"]["should return false when the path does not exist"] = function()
  eq(false, Path.new("dne.md"):is_dir())
end

T["mkdir"] = new_set()

T["mkdir"]["should make a directory"] = function()
  local dir = Path.temp()
  eq(false, dir:exists())
  dir:mkdir()
  eq(true, dir:exists())
  eq(true, dir:is_dir())
  eq(false, dir:is_file())

  dir:mkdir { exist_ok = true }
  eq(true, dir:exists())
  has_error(function()
    dir:mkdir { exist_ok = false }
  end)

  dir:rmdir()
  eq(false, dir:exists())
end

T["mkdir"]["should make a directory and its parents"] = function()
  local base_dir = Path.temp()
  local dir = base_dir / "foo"
  eq(false, base_dir:exists())
  eq(false, dir:exists())

  dir:mkdir { parents = true }
  eq(true, base_dir:exists())
  eq(true, dir:exists())

  dir:rmdir()
  eq(false, dir:exists())

  base_dir:rmdir()
  eq(false, base_dir:exists())
end

T["mkdir"]["should rename a file"] = function()
  local temp_file = Path.temp()
  temp_file:touch()
  eq(true, temp_file:is_file())

  local target = Path.temp()
  eq(false, target:exists())

  temp_file:rename(target)
  eq(true, target:is_file())
  eq(false, temp_file:is_file())

  target:unlink()
  eq(false, target:is_file())
end

T["mkdir"]["should rename a directory"] = function()
  local temp_dir = Path.temp()
  temp_dir:mkdir()
  eq(true, temp_dir:is_dir())

  local target = Path.temp()
  eq(false, target:exists())

  temp_dir:rename(target)
  eq(true, target:is_dir())
  eq(false, temp_dir:is_dir())

  target:rmdir()
  eq(false, target:exists())
end

return T
