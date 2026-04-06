vim.opt.runtimepath:prepend(".")
vim.pack.add({ "https://github.com/echasnovski/mini.test" })

require("mini.test").setup({ collect = { emulate_busted = true } })

MiniTest.run({
  collect = {
    find_files = function()
      return vim.fn.globpath("spec", "**/*_spec.lua", true, true)
    end,
  },
})
