local M = {}

---@param opts table|nil
---@return table
function M.setup(opts)
  require("luogu.config").setup(opts)
  return M
end

---@param pid string
function M.open(pid)
  require("luogu.ui.problem").open(pid)
end

function M.list()
  require("luogu.ui.list").open("problems")
end

---@param pid string|nil
function M.submit(pid)
  require("luogu.ui.problem").submit(pid)
end

function M.login()
  require("luogu.auth").login()
end

function M.logout()
  require("luogu.auth").logout()
end

return M
