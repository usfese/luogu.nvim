if vim.fn.has("nvim-0.10") ~= 1 then
  return
end

vim.api.nvim_create_user_command("Luogu", function(opts)
  require("luogu.command").run(opts.fargs)
end, {
  nargs = "*",
  desc = "Luogu: browse problems, open, submit",
  complete = function(arglead, cmdline, cursorpos)
    return require("luogu.command").complete(arglead, cmdline, cursorpos)
  end,
})

require("luogu.highlights").setup()
