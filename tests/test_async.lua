local AsyncExecutor = require("obsidian.async").AsyncExecutor
local ThreadPoolExecutor = require("obsidian.async").ThreadPoolExecutor

describe("AsyncExecutor.map()", function()
  it("should maintain order of results with a table of args", function()
    local executor = AsyncExecutor.new()
    local task_args = { { 1 }, { 2 }, { 3 }, { 4 } }

    executor:map(
      function(id)
        local uv = vim.uv
        uv.sleep(100)
        return id
      end,
      task_args,
      function(results)
        MiniTest.expect.equality(results, { { 1 }, { 2 }, { 3 }, { 4 } })
      end
    )

    executor:join(500)
  end)

  it("should maintain order of results with a generator of args", function()
    local executor = AsyncExecutor.new()
    local task_args = { 1, 2, 3, 4 }
    local i = 0
    local function task_args_gen()
      i = i + 1
      return task_args[i]
    end

    executor:map(
      function(id)
        local uv = vim.uv
        uv.sleep(100)
        return id
      end,
      task_args_gen,
      function(results)
        MiniTest.expect.equality(results, { { 1 }, { 2 }, { 3 }, { 4 } })
      end
    )

    executor:join(500)
  end)
end)

describe("ThreadPoolExecutor.map()", function()
  it("should maintain order of results with a table of args", function()
    local executor = ThreadPoolExecutor.new()
    local task_args = { { 1 }, { 2 }, { 3 }, { 4 } }

    executor:map(
      function(id)
        local uv = vim.uv
        uv.sleep(100)
        return id
      end,
      task_args,
      function(results)
        MiniTest.expect.equality(results, { { 1 }, { 2 }, { 3 }, { 4 } })
      end
    )

    executor:join(500)
  end)

  it("should maintain order of results with a generator of args", function()
    local executor = ThreadPoolExecutor.new()
    local task_args = { 1, 2, 3, 4 }
    local i = 0
    local function task_args_gen()
      i = i + 1
      return task_args[i]
    end

    executor:map(
      function(id)
        local uv = vim.uv
        uv.sleep(100)
        return id
      end,
      task_args_gen,
      function(results)
        MiniTest.expect.equality(results, { { 1 }, { 2 }, { 3 }, { 4 } })
      end
    )

    executor:join(500)
  end)
end)
