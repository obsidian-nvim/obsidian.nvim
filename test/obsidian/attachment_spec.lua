local M = require "obsidian.attachments"

local url_with_params = [[
https://private-user-images.githubusercontent.com/111681693/437674259-e21d6c2d-c5b5-47b1-8ee8-dcc2e03fbc3a.jpg?jwt=eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJnaXRodWIuY29tIiwiYXVkIjoicmF3LmdpdGh1YnVzZXJjb250ZW50LmNvbSIsImtleSI6ImtleTUiLCJleHAiOjE3NDU2NTEyNDQsIm5iZiI6MTc0NTY1MDk0NCwicGF0aCI6Ii8xMTE2ODE2OTMvNDM3Njc0MjU5LWUyMWQ2YzJkLWM1YjUtNDdiMS04ZWU4LWRjYzJlMDNmYmMzYS5qcGc_WC1BbXotQWxnb3JpdGhtPUFXUzQtSE1BQy1TSEEyNTYmWC1BbXotQ3JlZGVudGlhbD1BS0lBVkNPRFlMU0E1M1BRSzRaQSUyRjIwMjUwNDI2JTJGdXMtZWFzdC0xJTJGczMlMkZhd3M0X3JlcXVlc3QmWC1BbXotRGF0ZT0yMDI1MDQyNlQwNzAyMjRaJlgtQW16LUV4cGlyZXM9MzAwJlgtQW16LVNpZ25hdHVyZT1kNTc5ZmY5Y2U2ZDUwOWFiYWJhYzQ1OTUyZjcyOGVlMDgxODQ1ZDQ0MDdlNDIyNjI1YmVlNjM0NTMyZTZhZTBhJlgtQW16LVNpZ25lZEhlYWRlcnM9aG9zdCJ9.Xkw8rMM9G0vB-uxpf9djM6Bm-x2D6mJExorLcsuWkBA
]]

local url_simple = [[https://gpanders.com/img/nvim-virtual-lines-3.png]]

local path_simple = "/home/runner/Notes/assets/image.png"

describe("is_remote", function()
  it("should recongize a url ending with file extension", function()
    local ok, ext = M.is_remote(url_simple)
    assert.equal(true, ok)
    assert.equal("png", ext)
  end)
  it("should recongize a long url not ending with file extension", function()
    local ok, ext = M.is_remote(url_with_params)
    assert.equal(true, ok)
    assert.equal("jpg", ext)
  end)
  it("should return false on file path", function()
    local ok = M.is_remote(path_simple)
    assert.equal(false, ok)
  end)
end)

describe("is_local", function()
  it("should recongize a file path", function()
    local ok, ext = M.is_local(path_simple)
    assert.equal(true, ok)
    assert.equal("png", ext)
  end)
  it("should return false on urls", function()
    local ok = M.is_local(url_simple)
    assert.equal(false, ok)
  end)
end)
