---@alias fixpoint.RequestHandler fun(self: fixpoint.ServerInstance, params: table): any?, string?
---@alias fixpoint.NotificationHandler fun(self: fixpoint.ServerInstance, params: table)

---@class fixpoint.ServerInstance : fixpoint.Server
---@field dispatchers vim.lsp.rpc.Dispatchers
---@field closing boolean
---@field request_id integer
---@field init_options? table Client's initializationOptions
---@field client_capabilities? lsp.ClientCapabilities Client's declared capabilities
---@field root_uri? string Client's root URI
---@field package _did_shutdown boolean

---@class fixpoint.Server
---@field name string Server name, reported in InitializeResult.serverInfo
---@field capabilities lsp.ServerCapabilities Capabilities to advertise
---@field root_markers? (string|string[])[] Files that identify the project root
---@field single_file_support boolean Work without a project root (default: true)
---@field requests table<string, fixpoint.RequestHandler>
---@field notifications table<string, fixpoint.NotificationHandler>
---@field on_init? fun(self: fixpoint.ServerInstance, params: lsp.InitializeParams)
---@field on_shutdown? fun(self: fixpoint.ServerInstance)
local Server = {}
Server.__index = Server

---@param name string
---@return fixpoint.Server
function Server.new(name)
  return setmetatable({
    name = name,
    capabilities = {},
    root_markers = nil,
    single_file_support = true,

    requests = {
      ["initialize"] = function(self, params)
        self.init_options = params.initializationOptions
        self.client_capabilities = params.capabilities
        self.root_uri = params.rootUri
        if self.on_init then
          self:on_init(params)
        end
        return { capabilities = self.capabilities, serverInfo = { name = self.name } }
      end,

      ["shutdown"] = function(self)
        self:_ensure_shutdown()
        return vim.NIL
      end,
    },

    notifications = {
      ["exit"] = function(self)
        self:_ensure_shutdown()
        self.closing = true
        self.dispatchers.on_exit(0, 0)
      end,
    },
  }, { __index = Server })
end

---@param self fixpoint.ServerInstance
---@param method string
---@param params table
---@param callback fun(err?: lsp.ResponseError, result?: any)
---@param notify_reply_callback? fun(request_id: integer)
---@return boolean success
---@return integer request_id
function Server:handle_request(method, params, callback, notify_reply_callback)
  self.request_id = self.request_id + 1

  local handler = self.requests[method]
  if handler then
    local ok, result, err = pcall(handler, self, params)
    if not ok then
      callback({ code = -32603, message = tostring(result) }, nil)
    elseif err then
      callback({ code = -32603, message = err }, nil)
    else
      callback(nil, result or {})
    end
  else
    callback({ code = -32601, message = "Method not found: " .. method }, nil)
  end

  if notify_reply_callback then
    notify_reply_callback(self.request_id)
  end

  return true, self.request_id
end

---@param self fixpoint.ServerInstance
---@param method string
---@param params table
function Server:handle_notify(method, params)
  local handler = self.notifications[method]
  if handler then
    local ok, err = pcall(handler, self, params)
    if not ok then
      self.dispatchers.on_error(vim.lsp.rpc.client_errors.INVALID_SERVER_MESSAGE, tostring(err))
    end
  end
end

---@param self fixpoint.ServerInstance
function Server:_ensure_shutdown()
  if not self._did_shutdown and self.on_shutdown then
    self:on_shutdown()
  end
  self._did_shutdown = true
end

--- Send a notification to the LSP client.
---@param self fixpoint.ServerInstance
---@param method string
---@param params table
function Server:notify_client(method, params)
  self.dispatchers.notification(method, params)
end

---@return vim.lsp.Config
function Server:build()
  local proto = self

  return {
    cmd = function(dispatchers)
      dispatchers.notification = vim.schedule_wrap(dispatchers.notification)
      dispatchers.on_error = vim.schedule_wrap(dispatchers.on_error)

      local srv = setmetatable({
        dispatchers = dispatchers,
        closing = false,
        request_id = 0,
      }, { __index = proto }) --[[@as fixpoint.ServerInstance]]

      return {
        request = function(method, params, callback, notify_reply_callback)
          return srv:handle_request(
            method,
            params,
            vim.schedule_wrap(callback),
            notify_reply_callback and vim.schedule_wrap(notify_reply_callback)
          )
        end,

        notify = function(method, params)
          srv:handle_notify(method, params)
          return true
        end,

        is_closing = function()
          return srv.closing
        end,

        terminate = function()
          srv:_ensure_shutdown()
          srv.closing = true
        end,
      }
    end,

    root_markers = self.root_markers,
    single_file_support = self.single_file_support,
  }
end

return Server
