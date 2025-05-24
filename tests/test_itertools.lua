local enumerate = require("obsidian.util").enumerate

describe("itertools.enumerate()", function()
  local function collect(iterator)
    local results = {}
    for i, x in iterator do
      results[i] = x
    end
    return results
  end

  it("should enumerate over arrays", function()
    MiniTest.expect.equality({ 1, 2, 3 }, collect(enumerate { 1, 2, 3 }))
  end)

  it("should enumerate over mapping keys", function()
    local results = {}
    for _, k in enumerate { a = 1, b = 2, c = 3 } do
      results[k] = true
    end
    MiniTest.expect.equality({ a = true, b = true, c = true }, results)
  end)
end)
