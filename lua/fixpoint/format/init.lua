local Server = require("fixpoint.server")

local M = Server.new("fixpoint_format")

M.capabilities = {
  documentFormattingProvider = true,
  documentRangeFormattingProvider = true,
  textDocumentSync = { openClose = true },
}

M.requests["textDocument/formatting"] = function()
  return {}
end

M.requests["textDocument/rangeFormatting"] = function()
  return {}
end

return M
