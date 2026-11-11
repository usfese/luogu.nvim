local M = {}

local BASE = "https://www.luogu.com.cn"

local STATUS_MSG = {
  [401] = "未登录或 Cookie 已失效，请 :Luogu login",
  [403] = "洛谷拒绝了请求（CSRF 或权限校验失败）",
  [404] = "资源不存在",
  [429] = "请求过于频繁，请稍后再试",
}

-- RFC 3986 unreserved set. vim.uri_encode leaves + & = / intact, which corrupts queries.
local UNRESERVED = {}
for c in ("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789-._~"):gmatch(".") do
  UNRESERVED[c] = true
end

---@param s any
---@return string
function M.urlencode(s)
  return (tostring(s):gsub(".", function(c)
    if UNRESERVED[c] then
      return c
    end
    return ("%%%02X"):format(c:byte())
  end))
end

---@param query table|nil
---@return string|nil
function M.encode_query(query)
  if not query then
    return nil
  end
  local keys = {}
  for k, v in pairs(query) do
    if v ~= nil and v ~= vim.NIL then
      keys[#keys + 1] = tostring(k)
    end
  end
  if #keys == 0 then
    return nil
  end
  table.sort(keys)
  local parts = {}
  for _, k in ipairs(keys) do
    local v = query[k]
    if v == nil then
      v = query[tonumber(k)]
    end
    parts[#parts + 1] = M.urlencode(k) .. "=" .. M.urlencode(v)
  end
  return table.concat(parts, "&")
end

local function one_line(s, max)
  s = (s or ""):gsub("%s+", " "):gsub("^%s+", "")
  if #s > max then
    s = s:sub(1, max)
  end
  return s
end

---@param opts table
---@param cb fun(res: table|nil, err: table|nil)
function M.request(opts, cb)
  if vim.fn.executable("curl") ~= 1 then
    vim.schedule(function()
      cb(nil, { msg = "luogu.nvim requires curl" })
    end)
    return
  end

  local cfg = require("luogu.config").get()
  local timeout = opts.timeout or cfg.http.timeout
  local url = BASE .. opts.path
  local query = M.encode_query(opts.query)
  if query then
    url = url .. "?" .. query
  end

  local args = {
    "curl",
    "-sS",
    "--compressed",
    "--max-time",
    ("%.3f"):format(timeout / 1000),
    "-A",
    cfg.http.user_agent,
    "-H",
    "referer: https://www.luogu.com.cn/",
    "-w",
    "\n%{http_code}",
  }

  -- -b "" turns on curl's cookie engine, so the WAF redirect cookie is carried
  -- on the follow-up request. Set-Cookie is only needed for GETs.
  args[#args + 1] = "-b"
  if opts.cookie and opts.cookie ~= "" then
    args[#args + 1] = opts.cookie
  else
    args[#args + 1] = ""
  end

  if opts.method ~= "POST" then
    args[#args + 1] = "-L"
    args[#args + 1] = "--max-redirs"
    args[#args + 1] = "3"
  end

  local headers = opts.headers or {}
  local has_content_type = false
  for k, v in pairs(headers) do
    if k:lower() == "content-type" then
      has_content_type = true
    end
    args[#args + 1] = "-H"
    args[#args + 1] = ("%s: %s"):format(k, v)
  end

  local stdin = nil
  if opts.method == "POST" then
    args[#args + 1] = "-X"
    args[#args + 1] = "POST"
    if not has_content_type then
      args[#args + 1] = "-H"
      args[#args + 1] = "content-type: application/json"
    end
    local body = opts.body
    if body == nil then
      body = ""
    elseif type(body) == "table" then
      body = vim.json.encode(body)
    end
    stdin = body
    args[#args + 1] = "--data-binary"
    args[#args + 1] = "@-"
  end

  args[#args + 1] = url

  local ok, err = pcall(vim.system, args, {
    text = true,
    timeout = math.floor(timeout) + 1000,
    stdin = stdin,
  }, function(obj)
    vim.schedule(function()
      local stdout = obj.stdout or ""
      local body, status = stdout:match("^(.*)\n(%d%d%d)%s*$")
      if not body then
        if obj.code ~= 0 then
          cb(nil, { msg = "curl 失败: " .. one_line(obj.stderr, 300) })
        else
          cb(nil, { msg = "curl 返回格式异常" })
        end
        return
      end
      if obj.code ~= 0 then
        cb(nil, { msg = "curl 失败: " .. one_line(obj.stderr, 300) })
        return
      end
      cb({ status = tonumber(status), body = body }, nil)
    end)
  end)

  if not ok then
    vim.schedule(function()
      cb(nil, { msg = "无法启动 curl: " .. tostring(err) })
    end)
  end
end

---@param opts table
---@param cb fun(data: any|nil, err: table|nil)
function M.json(opts, cb)
  M.request(opts, function(res, err)
    if err then
      return cb(nil, err)
    end
    if res.status < 200 or res.status > 299 then
      local msg = STATUS_MSG[res.status] or ("HTTP %d: %s"):format(res.status, one_line(res.body, 200))
      return cb(nil, { msg = msg, status = res.status, body = res.body })
    end
    if res.body:match("^%s*<") then
      local challenge = res.body:find("<script>var _%$", 1) ~= nil
      return cb(nil, {
        msg = challenge and "洛谷反爬校验：请求太快了，稍后再试"
          or "洛谷接口变更：需要更新 luogu.nvim",
        status = res.status,
        body = res.body,
      })
    end
    local decoded, data = pcall(vim.json.decode, res.body)
    if not decoded then
      return cb(nil, { msg = "洛谷返回了非 JSON 响应", status = res.status, body = res.body })
    end
    cb(data, nil)
  end)
end

M.BASE = BASE
M.STATUS_MSG = STATUS_MSG

return M
