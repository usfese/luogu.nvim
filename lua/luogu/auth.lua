local M = {}

local function cookie_path()
  return vim.fs.joinpath(require("luogu.config").data_dir(), "cookie")
end

local function strip_prefix(value)
  value = value:gsub("^%s*[Cc][Oo][Oo][Kk][Ii][Ee]:%s*", "")
  value = value:gsub("^%s+", "")
  return (value:gsub("%s+$", ""))
end

---@return string cookie header, or "" when not logged in
function M.get_cookie()
  local cfg = require("luogu.config").get()
  if type(cfg.cookie) == "string" and cfg.cookie ~= "" then
    return strip_prefix(cfg.cookie)
  end

  local path = cookie_path()
  if vim.fn.filereadable(path) == 0 then
    return ""
  end
  local ok, lines = pcall(vim.fn.readfile, path, "", 1)
  if not ok or type(lines) ~= "table" or not lines[1] then
    return ""
  end
  return strip_prefix(lines[1])
end

---@param cookie string
---@return string|nil
function M.parse_uid(cookie)
  if type(cookie) ~= "string" then
    return nil
  end
  return cookie:match("_uid=(%d+)")
end

function M.login()
  local raw = vim.fn.inputsecret("洛谷 Cookie: ")
  if type(raw) ~= "string" or raw == "" then
    return
  end
  if raw:find("[\r\n]") then
    return vim.notify("Cookie 不能包含换行", vim.log.levels.ERROR)
  end

  local candidate = strip_prefix(raw)
  if not (candidate:find("_uid=", 1, true) and candidate:find("__client_id=", 1, true)) then
    return vim.notify("Cookie 必须包含 __client_id 和 _uid", vim.log.levels.ERROR)
  end

  require("luogu.api").validate_cookie(candidate, function(res, err)
    if not res then
      return vim.notify(err and err.msg or "登录失败", vim.log.levels.ERROR)
    end

    local path = cookie_path()
    vim.fn.mkdir(require("luogu.config").data_dir(), "p")
    vim.fn.writefile({ candidate }, path)
    pcall(vim.uv.fs_chmod, path, 384) -- 0600

    local function report(name)
      local label = name and ("%s (%s)"):format(name, res.uid) or tostring(res.uid)
      vim.notify("登录成功：" .. label, vim.log.levels.INFO)
    end

    if res.name then
      return report(res.name)
    end
    require("luogu.api").user(res.uid, function(user, uerr)
      report(user and not uerr and user.name or nil)
    end)
  end)
end

function M.logout()
  vim.fn.delete(cookie_path())
  local cfg = require("luogu.config").get()
  if type(cfg.cookie) == "string" and cfg.cookie ~= "" then
    vim.notify("已删除 Cookie 文件；config.cookie 仍会生效，请从配置中移除", vim.log.levels.WARN)
  else
    vim.notify("已退出登录", vim.log.levels.INFO)
  end
end

---@return boolean
function M.require_login()
  if M.get_cookie() ~= "" then
    return true
  end
  vim.notify("未登录：请先 :Luogu login", vim.log.levels.WARN)
  return false
end

M.cookie_path = cookie_path

return M
