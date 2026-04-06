local FsWatcher = require("fixpoint.fswatcher")
local eq = MiniTest.expect.equality

local function request(client, method, params)
  local result, err
  local done = false
  client.request(method, params or {}, function(e, r)
    err = e
    result = r
    done = true
  end)
  vim.wait(1000, function()
    return done
  end)
  return result, err
end

local function start()
  return FsWatcher:build().cmd({
    notification = function() end,
    on_error = function() end,
    on_exit = function() end,
  })
end

local function tmpfile(dir, name)
  local path = dir .. "/" .. name
  local f = io.open(path, "w")
  f:write("initial")
  f:close()
  return path, vim.uri_from_fname(path)
end

describe("FsWatcher", function()
  local tmpdir
  local original_checktime

  before_each(function()
    tmpdir = vim.fn.tempname()
    vim.fn.mkdir(tmpdir, "p")
    original_checktime = vim.cmd.checktime
  end)

  after_each(function()
    vim.cmd.checktime = original_checktime
    vim.fn.delete(tmpdir, "rf")
  end)

  it("calls checktime when a watched file changes", function()
    local checked = {}
    vim.cmd.checktime = function(bufnr)
      table.insert(checked, bufnr)
    end

    local client = start()
    request(client, "initialize")
    local path, uri = tmpfile(tmpdir, "a.txt")
    client.notify("textDocument/didOpen", { textDocument = { uri = uri } })

    local f = io.open(path, "w")
    f:write("change")
    f:close()

    vim.wait(500, function()
      return #checked > 0
    end)

    assert(#checked > 0, "checktime was not called")

    request(client, "shutdown")
  end)

  it("debounces checktime across rapid changes", function()
    local checked = {}
    vim.cmd.checktime = function(bufnr)
      table.insert(checked, bufnr)
    end

    local client = start()
    request(client, "initialize")
    local path, uri = tmpfile(tmpdir, "b.txt")
    client.notify("textDocument/didOpen", { textDocument = { uri = uri } })

    for i = 1, 5 do
      local f = io.open(path, "w")
      f:write("change " .. i)
      f:close()
    end

    vim.wait(500, function()
      return #checked > 0
    end)

    eq(#checked, 1)

    request(client, "shutdown")
  end)

  it("stops calling checktime after didClose", function()
    local checked = {}
    vim.cmd.checktime = function(bufnr)
      table.insert(checked, bufnr)
    end

    local client = start()
    request(client, "initialize")
    local path, uri = tmpfile(tmpdir, "c.txt")
    client.notify("textDocument/didOpen", { textDocument = { uri = uri } })
    client.notify("textDocument/didClose", { textDocument = { uri = uri } })

    local f = io.open(path, "w")
    f:write("change")
    f:close()

    vim.wait(200, function() end)

    eq(#checked, 0)

    request(client, "shutdown")
  end)

  it("stops calling checktime after shutdown", function()
    local checked = {}
    vim.cmd.checktime = function(bufnr)
      table.insert(checked, bufnr)
    end

    local client = start()
    request(client, "initialize")
    local path, uri = tmpfile(tmpdir, "d.txt")
    client.notify("textDocument/didOpen", { textDocument = { uri = uri } })
    request(client, "shutdown")

    local f = io.open(path, "w")
    f:write("change")
    f:close()

    vim.wait(200, function() end)

    eq(#checked, 0)
  end)
end)
