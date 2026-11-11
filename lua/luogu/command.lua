local M = {}

local LOG = vim.log.levels
local USAGE = "用法: :Luogu [list|open <pid>|submit [pid]|lang [key]|login|logout|record <rid>|sync]"

local SUBCOMMANDS = { "list", "open", "submit", "lang", "login", "logout", "record", "sync" }

local function err(msg)
  vim.notify(msg, LOG.ERROR)
end

---@param fargs string[]
function M.run(fargs)
  fargs = fargs or {}
  local sub = fargs[1]

  if not sub or sub == "" then
    return require("luogu.ui.list").open("menu")
  end

  if sub == "list" then
    return require("luogu.ui.list").open("problems")
  elseif sub == "open" then
    if not fargs[2] or fargs[2] == "" then
      return err(USAGE)
    end
    return require("luogu.ui.problem").open(fargs[2])
  elseif sub == "submit" then
    return require("luogu.ui.problem").submit(fargs[2])
  elseif sub == "lang" then
    return require("luogu.ui.problem").pick_language(fargs[2])
  elseif sub == "login" then
    return require("luogu.auth").login()
  elseif sub == "logout" then
    return require("luogu.auth").logout()
  elseif sub == "record" then
    if not fargs[2] or fargs[2] == "" then
      return err(USAGE)
    end
    return require("luogu.ui.result").open(fargs[2])
  elseif sub == "sync" then
    return require("luogu.ui.list").sync()
  end

  if sub:match("^[%w_]+$") then
    return require("luogu.ui.problem").open(sub)
  end

  err(USAGE)
end

---@return string[]
local function cached_pids(arglead)
  local out = {}
  local ok, ui = pcall(require, "luogu.ui.list")
  if not ok then
    return out
  end
  local data = ui.get_data()
  if not data or not data.result then
    return out
  end
  for i, problem in ipairs(data.result) do
    if i > 50 then
      break
    end
    local pid = problem.pid
    if pid and pid:sub(1, #arglead) == arglead then
      out[#out + 1] = pid
    end
  end
  return out
end

---@param arglead string
---@param cmdline string|nil
---@return string[]
function M.complete(arglead, cmdline)
  arglead = arglead or ""

  local parts = vim.split(vim.trim((cmdline or ""):gsub("^%s*:?%s*", "")), "%s+", { trimempty = true })
  if parts[1] == "Luogu" then
    table.remove(parts, 1)
  end
  local sub = parts[1]

  if (sub == "open" or sub == "submit") and #parts <= 2 then
    return cached_pids(arglead)
  end

  local out = {}
  for _, name in ipairs(SUBCOMMANDS) do
    if name:sub(1, #arglead) == arglead then
      out[#out + 1] = name
    end
  end
  return out
end

return M
