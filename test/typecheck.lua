local tmp = vim.fn.tempname()
vim.fn.mkdir(tmp, "p")

local config_path = tmp .. "/luarc.json"
local config = vim.json.encode({
  Lua = {
    runtime = { version = "LuaJIT" },
    workspace = {
      library = { vim.env.VIMRUNTIME, "${3rd}/luv/library" },
      checkThirdParty = false,
    },
  },
})

local f = io.open(config_path, "w")
f:write(config)
f:close()

local result = os.execute(
  string.format(
    "lua-language-server --check %s --checklevel=Warning --configpath=%s",
    vim.fn.fnamemodify("lua", ":p"),
    config_path
  )
)

vim.fn.delete(tmp, "rf")
os.exit((result == true or result == 0) and 0 or 1)
