local M = {}
local upstream = require("luogu.upstream")
local lc = upstream.require

local started = false

local function start()
  if started and upstream.env._Lc_state and upstream.env._Lc_state.menu then
    return true
  end
  local leetcode = lc("leetcode")
  lc("leetcode.config").apply({
    plugins = { non_standalone = true },
    storage = {
      home = vim.fn.stdpath("data") .. "/luogu",
      cache = vim.fn.stdpath("cache") .. "/luogu",
    },
  })
  lc("leetcode.config").translator = true
  leetcode.setup_cmds = function() end
  started = leetcode.start(false)
  return started
end

function M.setup()
  vim.api.nvim_create_user_command("Luogu", function(opts)
    if not start() then return end
    local sub, arg = opts.fargs[1], opts.fargs[2]
    if not sub or sub == "menu" then
      lc("leetcode.command").menu()
    elseif sub == "list" then
      require("luogu.list").open()
    elseif sub == "open" and arg then
      require("luogu.question").open(arg)
    elseif sub == "login" then
      require("luogu.list").cookie_prompt()
    elseif sub == "submit" then
      lc("leetcode.command").q_submit()
    elseif sub == "desc" then
      lc("leetcode.command").desc_toggle()
    else
      vim.notify("用法: :Luogu [menu|list|open <pid>|login|submit|desc]", vim.log.levels.ERROR)
    end
  end, { nargs = "*", force = true, complete = function() return { "menu", "list", "open", "login", "submit", "desc" } end })
end

return M
