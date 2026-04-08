local Server = require("fixpoint.server")

---@class fixpoint.FsWatcher : fixpoint.ServerInstance
---@field watchers table<string, uv.uv_fs_event_t>
---@field private _timer uv.uv_timer_t
---@field private _pending table<string, true>
local M = Server.new("fixpoint_fswatcher")

M.capabilities = { textDocumentSync = { openClose = true } }

local DEBOUNCE_MS = 50

local function stop_watcher(w)
  if w and not w:is_closing() then
    w:stop()
    w:close()
  end
end

---@param uri string
function M:_schedule_checktime(uri)
  if self._timer:is_closing() then
    return
  end
  self._pending[uri] = true
  self._timer:start(
    DEBOUNCE_MS,
    0,
    vim.schedule_wrap(function()
      for pending_uri in pairs(self._pending) do
        local bufnr = vim.uri_to_bufnr(pending_uri)
        pcall(vim.cmd.checktime, bufnr)
      end
      self._pending = {}
    end)
  )
end

---@param uri string
function M:watch(uri)
  stop_watcher(self.watchers[uri])

  local w = vim.uv.new_fs_event()
  if not w then
    local msg = "fixpoint_fswatcher: failed to create fs_event for " .. uri
    vim.lsp.log.warn(msg)
    vim.notify(msg, vim.log.levels.WARN)
    return
  end

  w:start(
    vim.uri_to_fname(uri),
    {},
    vim.schedule_wrap(function()
      self:watch(uri)
      self:_schedule_checktime(uri)
    end)
  )

  self.watchers[uri] = w
end

function M:on_init()
  self.watchers = {}
  self._timer = assert(vim.uv.new_timer())
  self._pending = {}

  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(buf)

    local is_file = name ~= "" and vim.api.nvim_buf_is_loaded(buf) and vim.bo[buf].buftype == ""

    if is_file then
      self:watch(vim.uri_from_fname(name))
    end
  end
end

---@param self fixpoint.FsWatcher
M.notifications["textDocument/didOpen"] = function(self, params)
  self:watch(params.textDocument.uri)
end

---@param self fixpoint.FsWatcher
M.notifications["textDocument/didClose"] = function(self, params)
  local uri = params.textDocument.uri
  stop_watcher(self.watchers[uri])
  self.watchers[uri] = nil
end

function M:on_shutdown()
  for uri, w in pairs(self.watchers) do
    stop_watcher(w)
    self.watchers[uri] = nil
  end

  if self._timer and not self._timer:is_closing() then
    self._timer:stop()
    self._timer:close()
  end
end

return M
