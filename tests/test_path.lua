local Path = require "obsidian.path"
local util = require "obsidian.util"

describe("Path.new()", function()
  it("should initialize with both method syntax and regular dot access", function()
    ---@type obsidian.Path
    local path

    path = Path.new "README.md"
    MiniTest.expect.equality("README.md", path.filename)

    path = Path:new "README.md"
    MiniTest.expect.equality("README.md", path.filename)
  end)

  it("should return same object when arg is already a path", function()
    local path = Path.new "README.md"
    MiniTest.expect.equality(path, Path.new(path))
  end)

  it("should init from a plenary path", function()
    local PlenaryPath = require "plenary.path"
    local path = Path.new "README.md"
    MiniTest.expect.equality(true, path == Path.new(PlenaryPath:new "README.md"))
  end)

  it("should raise an error if 2 args are passed and the first isn't Path", function()
    MiniTest.expect.error(function()
      ---@diagnostic disable-next-line
      Path.new(1, "bar")
    end)
  end)

  if util.get_os() == util.OSType.Windows then
    it("should normalize lowercase c drives on windows correctly", function()
      local path = Path:new "c:/foo/bar"
      MiniTest.expect.equality(path.filename, "C:/foo/bar")
    end)
  end
end)

describe("Path.is_path_obj()", function()
  it("should return true for obsidian.Path objects", function()
    local path = Path.new "README.md"
    MiniTest.expect.equality(true, Path.is_path_obj(path))
  end)

  it("should return false for all other kinds of objects", function()
    MiniTest.expect.equality(false, Path.is_path_obj(1))
    MiniTest.expect.equality(false, Path.is_path_obj { a = 2 })
    MiniTest.expect.equality(false, Path.is_path_obj(nil))
  end)
end)

describe("Path.__eq", function()
  it("should compare with other paths correctly", function()
    MiniTest.expect.equality(true, Path:new "README.md" == Path:new "README.md")
    MiniTest.expect.equality(true, Path:new "/foo" == Path:new "/foo/")

    local path = Path:new "README.md"
    local _ = path.name
    MiniTest.expect.equality(true, path == Path:new "README.md")
    MiniTest.expect.equality(true, path == Path.new(path))
  end)
end)

describe("Path.__div", function()
  it("should join paths", function()
    assert(Path:new "/foo/" / "bar" == Path:new "/foo/bar")
  end)
end)

describe("Path.name", function()
  it("should return final component", function()
    MiniTest.expect.equality("bar.md", Path:new("/foo/bar.md").name)
  end)
end)

describe("Path.suffix", function()
  it("should return final suffix", function()
    MiniTest.expect.equality(".md", Path:new("/foo/bar.md").suffix)
    MiniTest.expect.equality(".gz", Path:new("/foo/bar.tar.gz").suffix)
  end)

  it("should return nil when there is no suffix", function()
    MiniTest.expect.equality(nil, Path:new("/foo/bar").suffix)
  end)
end)

describe("Path.suffix", function()
  it("should return all extensions", function()
    MiniTest.expect.equality({ ".md" }, Path:new("/foo/bar.md").suffixes)
    MiniTest.expect.equality({ ".tar", ".gz" }, Path:new("/foo/bar.tar.gz").suffixes)
  end)

  it("should return empty list when there is no suffix", function()
    MiniTest.expect.equality({}, Path:new("/foo/bar").suffixes)
  end)
end)

describe("Path.stem", function()
  it("should return the final name without suffix", function()
    MiniTest.expect.equality("bar", Path:new("/foo/bar.md").stem)
    MiniTest.expect.equality(nil, Path:new("/").stem)
  end)
end)

describe("Path.with_suffix()", function()
  it("should create a new path with the new suffix", function()
    MiniTest.expect.equality(true, Path:new("/foo/bar.md"):with_suffix ".tar.gz" == Path.new "/foo/bar.tar.gz")
    MiniTest.expect.equality(true, Path:new("/foo/bar.tar.gz"):with_suffix ".bz2" == Path.new "/foo/bar.tar.bz2")
    MiniTest.expect.equality(true, Path:new("/foo/bar"):with_suffix ".md" == Path.new "/foo/bar.md")
  end)

  it("should not add anything else to the filename", function()
    MiniTest.expect.equality(Path.new "foo-bar.png", Path.new("foo-bar"):with_suffix ".png")
  end)

  it("should fail when there is no stem", function()
    MiniTest.expect.error(function()
      Path.new("/"):with_suffix ".png"
    end)
  end)

  it("should allow appending the suffix instead of replacing it", function()
    MiniTest.expect.equality(Path.new "johnny.md", Path.new("johnny.decimal"):with_suffix ".md")
    MiniTest.expect.equality(Path.new "johnny.decimal.md", Path.new("johnny.decimal"):with_suffix(".md", true))
  end)
end)

describe("Path.is_absolute()", function()
  it("should work for windows or unix paths", function()
    assert(Path:new("/foo/"):is_absolute())
    if util.get_os() == util.OSType.Windows then
      assert(Path:new("C:/foo/"):is_absolute())
      assert(Path:new("C:\\foo\\"):is_absolute())
    end
  end)
end)

describe("Path.joinpath()", function()
  it("can join multiple", function()
    MiniTest.expect.equality(true, Path.new "foo/bar/baz.md" == Path.new("foo"):joinpath("bar", "baz.md"))
    MiniTest.expect.equality(true, Path.new "foo/bar/baz.md" == Path.new("foo/"):joinpath("bar/", "baz.md"))
    MiniTest.expect.equality(true, Path.new "foo/bar/baz.md" == Path.new("foo/"):joinpath("bar/", "/baz.md"))
  end)
end)

describe("Path.relative_to()", function()
  it("should work on absolute paths", function()
    MiniTest.expect.equality("baz.md", Path:new("/foo/bar/baz.md"):relative_to("/foo/bar/").filename)
    MiniTest.expect.equality("baz.md", Path:new("/foo/bar/baz.md"):relative_to("/foo/bar").filename)
    MiniTest.expect.equality("baz.md", Path:new("/baz.md"):relative_to("/").filename)
  end)

  it("should raise an error when the relative path can't be resolved", function()
    MiniTest.expect.error(function()
      Path:new("/bar/bar/baz.md"):relative_to "/foo/"
    end)

    MiniTest.expect.error(function()
      Path:new("bar/bar/baz.md"):relative_to "/bar"
    end)
  end)

  it("should work on relative paths", function()
    MiniTest.expect.equality("img.png", Path:new("assets/img.png"):relative_to("assets").filename)
    MiniTest.expect.equality("img.png", Path:new("assets/img.png"):relative_to("./assets").filename)

    MiniTest.expect.equality("assets/img.png", Path:new("assets/img.png"):relative_to("./").filename)
    MiniTest.expect.equality("assets/img.png", Path:new("./assets/img.png"):relative_to("./").filename)
  end)
end)

describe("Path.parent()", function()
  it("should get the parent of the current", function()
    MiniTest.expect.equality(Path.new("/foo/bar/README.md"):parent(), Path.new "/foo/bar")
  end)

  it("should return './' for an unresolved name to match Python pathlib API", function()
    MiniTest.expect.equality(Path.new "./", Path.new("foo-bar"):parent())
  end)

  it("should return '/' for '/' to match Python pathlib API", function()
    MiniTest.expect.equality(Path.new "/", Path.new("/"):parent())
  end)
end)

describe("Path.parents()", function()
  it("should collect all logical parents", function()
    MiniTest.expect.equality(
      Path.new("/foo/bar/README.md"):parents(),
      { Path.new "/foo/bar", Path.new "/foo", Path.new "/" }
    )
  end)
end)

describe("Path.resolve()", function()
  it("should always resolve to the absolute path when it exists", function()
    MiniTest.expect.equality(
      vim.fs.normalize(assert(vim.uv.fs_realpath "README.md")),
      Path.new("README.md"):resolve().filename
    )
  end)

  it("should always resolve to an absolute path if a parent exists", function()
    MiniTest.expect.equality(
      vim.fs.normalize(assert(vim.uv.fs_realpath ".")) .. "/tmp/dne.md",
      Path.new("tmp/dne.md"):resolve().filename
    )

    MiniTest.expect.equality(
      vim.fs.normalize(assert(vim.uv.fs_realpath ".")) .. "/dne.md",
      Path.new("dne.md"):resolve().filename
    )
  end)
end)

describe("Path.exists()", function()
  it("should return true when the path exists", function()
    MiniTest.expect.equality(true, Path.new("README.md"):exists())
    MiniTest.expect.equality(true, Path.new("lua"):exists())
  end)

  it("should return false when the path does not exists", function()
    MiniTest.expect.equality(false, Path.new("dne.md"):exists())
  end)
end)

describe("Path.is_file()", function()
  it("should return true when the path is a file", function()
    MiniTest.expect.equality(true, Path.new("README.md"):is_file())
    MiniTest.expect.equality(false, Path.new("README.md"):is_dir())
  end)

  it("should return false when the path is a directory", function()
    MiniTest.expect.equality(false, Path.new("lua"):is_file())
  end)
end)

describe("Path.is_dir()", function()
  it("should return true when the path is a directory", function()
    MiniTest.expect.equality(true, Path.new("lua"):is_dir())
    MiniTest.expect.equality(false, Path.new("lua"):is_file())
  end)

  it("should return false when the path is a file", function()
    MiniTest.expect.equality(false, Path.new("README.md"):is_dir())
  end)

  it("should return false when the path does not exist", function()
    MiniTest.expect.equality(false, Path.new("dne.md"):is_dir())
  end)
end)

describe("Path.mkdir()", function()
  it("should make a directory", function()
    local dir = Path.temp()
    MiniTest.expect.equality(false, dir:exists())

    dir:mkdir()
    MiniTest.expect.equality(true, dir:exists())
    MiniTest.expect.equality(true, dir:is_dir())
    MiniTest.expect.equality(false, dir:is_file())

    dir:mkdir { exist_ok = true }
    MiniTest.expect.equality(true, dir:exists())

    MiniTest.expect.error(function()
      dir:mkdir { exist_ok = false }
    end)

    dir:rmdir()
    MiniTest.expect.equality(false, dir:exists())
  end)

  it("should make a directory and its parents", function()
    local base_dir = Path.temp()
    local dir = base_dir / "foo"
    MiniTest.expect.equality(false, base_dir:exists())
    MiniTest.expect.equality(false, dir:exists())

    dir:mkdir { parents = true }
    MiniTest.expect.equality(true, base_dir:exists())
    MiniTest.expect.equality(true, dir:exists())

    dir:rmdir()
    MiniTest.expect.equality(false, dir:exists())

    base_dir:rmdir()
    MiniTest.expect.equality(false, base_dir:exists())
  end)

  it("should rename a file", function()
    local temp_file = Path.temp()
    temp_file:touch()
    MiniTest.expect.equality(true, temp_file:is_file())

    local target = Path.temp()
    MiniTest.expect.equality(false, target:exists())

    temp_file:rename(target)
    MiniTest.expect.equality(true, target:is_file())
    MiniTest.expect.equality(false, temp_file:is_file())

    target:unlink()
    MiniTest.expect.equality(false, target:is_file())
  end)

  it("should rename a directory", function()
    local temp_dir = Path.temp()
    temp_dir:mkdir()
    MiniTest.expect.equality(true, temp_dir:is_dir())

    local target = Path.temp()
    MiniTest.expect.equality(false, target:exists())

    temp_dir:rename(target)
    MiniTest.expect.equality(true, target:is_dir())
    MiniTest.expect.equality(false, temp_dir:is_dir())

    target:rmdir()
    MiniTest.expect.equality(false, target:exists())
  end)
end)
