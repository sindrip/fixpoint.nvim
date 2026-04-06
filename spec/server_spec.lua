local Server = require("fixpoint.server")
local eq = MiniTest.expect.equality

local function request(client, method, params)
  local result, err
  local done = false
  local _, id = client.request(method, params or {}, function(e, r)
    err = e
    result = r
    done = true
  end)
  vim.wait(1000, function()
    return done
  end)
  return result, err, id
end

local function start(srv)
  return srv:build().cmd({
    notification = function() end,
    on_error = function() end,
    on_exit = function() end,
  })
end

describe("Server", function()
  it("creates a server with default state", function()
    local srv = Server.new("test")
    eq(srv.name, "test")
    eq(srv.single_file_support, true)
    eq(srv.root_markers, nil)
    eq(type(srv.capabilities), "table")
  end)

  describe("build", function()
    it("returns cmd, root_markers, and single_file_support", function()
      local srv = Server.new("test")
      srv.root_markers = { ".git" }
      srv.single_file_support = false

      local config = srv:build()
      eq(type(config.cmd), "function")
      eq(config.root_markers, { ".git" })
      eq(config.single_file_support, false)
    end)
  end)

  describe("requests", function()
    it("responds to initialize with capabilities", function()
      local srv = Server.new("test")
      srv.capabilities = { testProvider = true }
      local client = start(srv)

      local result = request(client, "initialize")
      eq(result.capabilities, { testProvider = true })
      eq(result.serverInfo.name, "test")
    end)

    it("responds to shutdown with vim.NIL", function()
      local client = start(Server.new("test"))
      request(client, "initialize")

      local result, err = request(client, "shutdown")
      eq(err, nil)
      eq(result, vim.NIL)
    end)

    it("returns method not found for unknown requests", function()
      local client = start(Server.new("test"))

      local _, err = request(client, "unknown/method")
      eq(err.code, -32601)
      assert(err.message:find("unknown/method"))
    end)

    it("tracks request ids", function()
      local client = start(Server.new("test"))
      local _, _, id1 = request(client, "initialize")
      local _, _, id2 = request(client, "shutdown")
      eq(id1, 1)
      eq(id2, 2)
    end)

    it("calls notify_reply_callback with request id", function()
      local client = start(Server.new("test"))

      local reply_id
      local done = false
      client.request("initialize", {}, function() end, function(id)
        reply_id = id
        done = true
      end)
      vim.wait(1000, function()
        return done
      end)

      eq(reply_id, 1)
    end)

    it("catches handler errors and returns internal error", function()
      local srv = Server.new("test")
      srv.requests["bad"] = function()
        error("something broke")
      end
      local client = start(srv)

      local _, err = request(client, "bad")
      eq(err.code, -32603)
      assert(err.message:find("something broke"))
    end)
  end)

  describe("notifications", function()
    it("exits and reports closing", function()
      local client = start(Server.new("test"))
      client.notify("exit")
      eq(client.is_closing(), true)
    end)

    it("ignores unknown notifications", function()
      local client = start(Server.new("test"))
      client.notify("unknown/notification", {})
    end)

    it("catches handler errors and reports via on_error", function()
      local reported
      local srv = Server.new("test")
      srv.notifications["bad"] = function()
        error("notify broke")
      end

      local client = srv:build().cmd({
        notification = function() end,
        on_error = function(code, err)
          reported = { code = code, err = err }
        end,
        on_exit = function() end,
      })

      client.notify("bad", {})
      vim.wait(1000, function()
        return reported ~= nil
      end)
      assert(reported.err:find("notify broke"))
    end)
  end)

  describe("lifecycle hooks", function()
    it("calls on_init during initialize", function()
      local init_params
      local srv = Server.new("test")
      function srv:on_init(params)
        init_params = params
      end
      local client = start(srv)

      request(client, "initialize", { rootUri = "file:///test" })
      eq(init_params.rootUri, "file:///test")
    end)

    it("calls on_shutdown once across multiple shutdown requests", function()
      local count = 0
      local srv = Server.new("test")
      function srv:on_shutdown()
        count = count + 1
      end
      local client = start(srv)

      request(client, "initialize")
      request(client, "shutdown")
      request(client, "shutdown")
      eq(count, 1)
    end)

    it("calls on_shutdown on exit if not yet shut down", function()
      local called = false
      local srv = Server.new("test")
      function srv:on_shutdown()
        called = true
      end
      local client = start(srv)

      client.notify("exit")
      eq(called, true)
    end)

    it("stores init params before calling on_init", function()
      local stored = {}
      local srv = Server.new("test")
      function srv:on_init()
        stored.init_options = self.init_options
        stored.client_capabilities = self.client_capabilities
        stored.root_uri = self.root_uri
      end
      local client = start(srv)

      request(client, "initialize", {
        rootUri = "file:///test",
        initializationOptions = { foo = "bar" },
        capabilities = { textDocument = {} },
      })
      eq(stored.init_options, { foo = "bar" })
      eq(stored.client_capabilities, { textDocument = {} })
      eq(stored.root_uri, "file:///test")
    end)
  end)

  describe("multi-client isolation", function()
    it("creates independent instances per client", function()
      local srv = Server.new("test")
      local client1 = start(srv)
      local client2 = start(srv)

      request(client1, "initialize")
      request(client2, "initialize")

      client1.notify("exit")
      eq(client1.is_closing(), true)
      eq(client2.is_closing(), false)

      client2.notify("exit")
      eq(client2.is_closing(), true)
    end)
  end)

  describe("notify_client", function()
    it("sends notification via dispatchers", function()
      local sent
      local srv = Server.new("test")
      srv.requests["test/notify"] = function(self)
        self:notify_client("custom/event", { data = 123 })
        return {}
      end

      local client = srv:build().cmd({
        notification = function(method, params)
          sent = { method = method, params = params }
        end,
        on_error = function() end,
        on_exit = function() end,
      })

      request(client, "test/notify")
      vim.wait(1000, function()
        return sent ~= nil
      end)
      eq(sent.method, "custom/event")
      eq(sent.params, { data = 123 })
    end)
  end)
end)
