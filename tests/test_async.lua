local async = require "obsidian.async"
local h = require "tests.helpers"
local eq = MiniTest.expect.equality
local T = MiniTest.new_set()

T["join handles a large synchronous queue without unpacking or recursion"] = function()
  local jobs, count, finished = {}, 0, false
  for _ = 1, 20000 do
    jobs[#jobs + 1] = function()
      count = count + 1
    end
  end
  async.run(function()
    async.join(10, jobs)
  end, function(err)
    eq(err, nil)
    finished = true
  end)
  eq(finished, true)
  eq(count, #jobs)
end

T["join bounds concurrent jobs and completes once"] = function()
  local jobs, active, peak, completed, finishes = {}, 0, 0, 0, 0
  for i = 1, 100 do
    jobs[#jobs + 1] = function()
      active = active + 1
      peak = math.max(peak, active)
      if i % 2 == 0 then
        async.await(1, function(done)
          vim.schedule(done)
        end)
      end
      active = active - 1
      completed = completed + 1
    end
  end
  async.run(function()
    async.join(10, jobs)
  end, function(err)
    eq(err, nil)
    finishes = finishes + 1
  end)
  h.wait(function()
    return finishes > 0
  end, { desc = "mixed synchronous and asynchronous jobs" })
  eq({ completed, active, peak, finishes }, { #jobs, 0, 10, 1 })
end

T["join handles empty queues and more slots than jobs"] = function()
  local count, finished = 0, false
  async.run(function()
    async.join(10, {})
    async.join(10, {
      function()
        count = count + 1
      end,
    })
  end, function(err)
    eq(err, nil)
    finished = true
  end)
  eq({ count, finished }, { 1, true })
end

return T
