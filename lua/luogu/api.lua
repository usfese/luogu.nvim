local M = {}

local http = require("luogu.http")
local latex = require("luogu.latex")

local LENTILLE = { ["x-lentille-request"] = "content-only" }

-- vim.json.decode turns JSON null into vim.NIL, which is truthy. Normalize it away
-- before any `or {}` / `if field` logic.
local function nn(v)
  if v == vim.NIL then
    return nil
  end
  return v
end

local function cookie()
  return require("luogu.auth").get_cookie()
end

--- Convert a JSON array-or-object into an array sorted by numeric key.
---@param value any
---@return table|nil
local function to_sorted_array(value)
  value = nn(value)
  if type(value) ~= "table" then
    return nil
  end
  if vim.islist(value) then
    local out = {}
    for _, v in ipairs(value) do
      out[#out + 1] = v
    end
    return out
  end
  local keys = {}
  for k in pairs(value) do
    keys[#keys + 1] = k
  end
  table.sort(keys, function(a, b)
    local na, nb = tonumber(a), tonumber(b)
    if na and nb then
      return na < nb
    end
    if na then
      return true
    end
    if nb then
      return false
    end
    return tostring(a) < tostring(b)
  end)
  local out = {}
  for _, k in ipairs(keys) do
    out[#out + 1] = value[k]
  end
  return out
end

---@param item table
---@return table
function M.normalize_summary(item)
  item = nn(item) or {}
  return {
    pid = nn(item.pid),
    name = latex.clean(nn(item.name)),
    difficulty = nn(item.difficulty) or 0,
    tags = nn(item.tags) or {},
    total_submit = nn(item.totalSubmit) or 0,
    total_accepted = nn(item.totalAccepted) or 0,
  }
end

---@param body table full /problem/:pid JSON body
---@return table
function M.normalize_problem(body)
  body = nn(body) or {}
  local data = nn(body.data) or {}
  local p = nn(data.problem) or {}

  local content = nn(p.content) or {}
  local limits = nn(p.limits) or {}
  local time_limit = nn(limits.time)
  local memory_limit = nn(limits.memory)

  local samples = {}
  for _, s in ipairs(to_sorted_array(p.samples) or {}) do
    s = nn(s) or {}
    samples[#samples + 1] = { nn(s[1]) or "", nn(s[2]) or "" }
  end

  local provider = nn(p.provider)

  return {
    pid = nn(p.pid),
    name = latex.clean(nn(p.name)),
    difficulty = nn(p.difficulty) or 0,
    tags = nn(p.tags) or {},
    content = {
      name = latex.clean(nn(content.name)),
      background = latex.clean(nn(content.background)),
      description = latex.clean(nn(content.description)),
      format_i = latex.clean(nn(content.formatI)),
      format_o = latex.clean(nn(content.formatO)),
      hint = latex.clean(nn(content.hint)),
    },
    samples = samples,
    limits = {
      time_ms = time_limit and nn(time_limit[1]) or nil,
      memory_kb = memory_limit and nn(memory_limit[1]) or nil,
    },
    accept_languages = nn(p.acceptLanguages) or {},
    last_language = nn(data.lastLanguage),
    last_code = nn(data.lastCode),
    total_submit = nn(p.totalSubmit) or 0,
    total_accepted = nn(p.totalAccepted) or 0,
    provider = type(provider) == "table" and nn(provider.name) or nil,
  }
end

---@param body table full /record/:rid JSON body
---@return table|nil
function M.normalize_record(body)
  body = nn(body) or {}
  local root = nn(body.currentData) or nn(body.data) or body
  local rec = nn(root.record) or nn(body.record)
  if type(rec) ~= "table" then
    return nil
  end

  local detail = nn(rec.detail) or {}

  local compile = nil
  local raw_compile = nn(detail.compileResult)
  if type(raw_compile) == "table" then
    compile = {
      success = raw_compile.success == true,
      message = nn(raw_compile.message),
    }
  end

  local judge = nil
  local raw_judge = nn(detail.judgeResult)
  if type(raw_judge) == "table" then
    judge = { subtasks = {}, score = nn(raw_judge.score) }
    for _, st in ipairs(to_sorted_array(raw_judge.subtasks) or {}) do
      st = nn(st) or {}
      local sub = {
        id = nn(st.id),
        score = nn(st.score),
        status = nn(st.status) or 0,
        time_ms = nn(st.time),
        memory_kb = nn(st.memory),
        test_cases = {},
      }
      for _, tc in ipairs(to_sorted_array(st.testCases) or {}) do
        tc = nn(tc) or {}
        sub.test_cases[#sub.test_cases + 1] = {
          id = nn(tc.id),
          status = nn(tc.status) or 0,
          time_ms = nn(tc.time),
          memory_kb = nn(tc.memory),
        }
      end
      judge.subtasks[#judge.subtasks + 1] = sub
    end
  end

  local show_status = nn(root.showStatus)

  return {
    rid = nn(rec.id),
    status = nn(rec.status) or 0,
    score = nn(rec.score),
    time_ms = nn(rec.time),
    memory_kb = nn(rec.memory),
    language = nn(rec.language),
    enable_o2 = rec.enableO2 == true or rec.enableO2 == 1,
    compile = compile,
    judge = judge,
    show_status = show_status ~= false,
    source_code = nn(rec.sourceCode),
  }
end

---@param body table full /problem/list JSON body
---@return table|nil payload, string|nil err
function M.normalize_list(body)
  body = nn(body) or {}
  local parent = nn(body.data)
  local problems = parent and nn(parent.problems)
  if type(problems) ~= "table" then
    return nil, "题库响应缺少数据（接口变更？）"
  end
  local result = {}
  for _, item in ipairs(to_sorted_array(problems.result) or {}) do
    result[#result + 1] = M.normalize_summary(item)
  end
  return {
    perPage = nn(problems.perPage) or #result,
    count = nn(problems.count) or #result,
    result = result,
  }
end

---@param params table|nil
function M.list(params, cb)
  params = params or {}
  local query = { page = params.page or 1, type = params.type or "P" }
  if params.keyword and params.keyword ~= "" then
    query.keyword = params.keyword
  end
  if params.difficulty ~= nil then
    query.difficulty = params.difficulty
  end

  http.json({ path = "/problem/list", query = query, headers = LENTILLE, cookie = cookie() }, function(data, err)
    if err then
      return cb(nil, err)
    end
    local payload, lerr = M.normalize_list(data)
    if not payload then
      return cb(nil, { msg = lerr })
    end
    cb(payload, nil)
  end)
end

function M.problem(pid, cb)
  http.json({ path = "/problem/" .. pid, headers = LENTILLE, cookie = cookie() }, function(data, err)
    if err then
      return cb(nil, err)
    end
    local d = data and nn(data.data)
    if not (d and nn(d.problem)) then
      return cb(nil, { msg = "题目响应缺少数据（接口变更？）" })
    end
    cb(M.normalize_problem(data), nil)
  end)
end

local tags_cache = nil

---@param body table full /_lfe/tags JSON body
---@return table|nil payload, string|nil err
function M.normalize_tags(body)
  body = nn(body) or {}
  local raw = nn(body.tags)
  if type(raw) ~= "table" then
    return nil, "标签响应缺少数据（接口变更？）"
  end
  local out = { tags = {}, by_id = {}, types = nn(body.types) or {} }
  for _, tag in ipairs(to_sorted_array(raw) or {}) do
    tag = nn(tag)
    if type(tag) == "table" then
      local id = nn(tag.id)
      if id ~= nil then
        local entry = { id = id, name = nn(tag.name), type = tag.type, parent = nn(tag.parent) }
        out.tags[#out.tags + 1] = entry
        out.by_id[id] = entry
      end
    end
  end
  return out
end

function M.tags(cb)
  if tags_cache then
    return cb(tags_cache, nil)
  end
  http.json({ path = "/_lfe/tags", cookie = cookie() }, function(data, err)
    if err then
      return cb(nil, err)
    end
    local payload, lerr = M.normalize_tags(data)
    if not payload then
      return cb(nil, { msg = lerr })
    end
    tags_cache = payload
    cb(payload, nil)
  end)
end

---@return table|nil cached tags payload without triggering a request
function M.tags_cached()
  return tags_cache
end

function M.user(uid, cb)
  http.json({ path = "/api/user/info/" .. tostring(uid), cookie = cookie() }, function(data, err)
    if err then
      return cb(nil, err)
    end
    local user = data and nn(data.user)
    if type(user) ~= "table" then
      return cb(nil, { msg = "用户响应缺少数据（接口变更？）" })
    end
    cb(user, nil)
  end)
end

---@param candidate string cookie header to test
function M.validate_cookie(candidate, cb)
  local uid = require("luogu.auth").parse_uid(candidate)
  if not uid then
    return cb(nil, { msg = "Cookie 中缺少 _uid" })
  end
  http.json({
    path = "/record/list",
    query = { user = uid, page = 1 },
    headers = LENTILLE,
    cookie = candidate,
  }, function(data, err)
    if err then
      if err.msg and not err.msg:find("Cookie") then
        err.msg = "Cookie 无效：" .. err.msg
      end
      return cb(nil, err)
    end
    local raw = nn(data) or {}
    local payload = nn(raw.data)
    local user = nn(raw.currentUser)
      or (payload and (nn(payload.currentUser) or nn(payload.user)))
      or nn(raw.user)
    cb({ uid = uid, name = type(user) == "table" and nn(user.name) or nil }, nil)
  end)
end

---@param html string
---@return string|nil
function M.parse_csrf(html)
  if type(html) ~= "string" then
    return nil
  end
  local token = html:match('<meta[^>]-name="csrf%-token"[^>]-content="([^"]+)"')
  if token and token ~= "" then
    return token
  end
  token = html:match('<meta[^>]-content="([^"]+)"[^>]-name="csrf%-token"')
  if token and token ~= "" then
    return token
  end
  token = html:match("<meta[^>]-name='csrf%-token'[^>]-content='([^']+)'")
  if token and token ~= "" then
    return token
  end
  return html:match("<meta[^>]-content='([^']+)'[^>]-name='csrf%-token'")
end

local function fetch_csrf(pid, cb)
  http.request({ path = "/problem/" .. pid, cookie = cookie() }, function(res, err)
    if err then
      return cb(nil, err)
    end
    if res.status < 200 or res.status > 299 then
      return cb(nil, { msg = ("无法打开题目页 (HTTP %d)"):format(res.status), status = res.status })
    end
    local token = M.parse_csrf(res.body)
    if not token then
      return cb(nil, { msg = "无法从题目页获取 CSRF token（可能未登录）" })
    end
    cb(token, nil)
  end)
end

---@param pid string
---@param code string
---@param lang_id integer
---@param o2 boolean|integer
function M.submit(pid, code, lang_id, o2, cb)
  local body = {
    code = code,
    lang = lang_id,
    enableO2 = (o2 == true or o2 == 1) and 1 or 0,
  }

  local function attempt(retried)
    fetch_csrf(pid, function(token, err)
      if not token then
        return cb(nil, err)
      end
      http.json({
        method = "POST",
        path = "/fe/api/problem/submit/" .. pid,
        headers = { ["x-csrf-token"] = token },
        body = body,
        cookie = cookie(),
      }, function(data, serr)
        if serr then
          local status = serr.status
          -- Luogu reports an absent or expired cookie as 403 UserNotLoggedInException.
          if serr.body and serr.body:find("NotLoggedIn", 1, true) then
            return cb(nil, {
              msg = "未登录或 Cookie 已失效，请 :Luogu login",
              status = status,
              body = serr.body,
            })
          end
          if not retried and (status == 403 or status == 419) then
            return attempt(true)
          end
          return cb(nil, serr)
        end
        local rid = nn(data) and (nn(data.rid) or (nn(data.data) and nn(data.data.rid)))
        if not rid then
          return cb(nil, { msg = "提交响应缺少 rid: " .. vim.inspect(data) })
        end
        cb({ rid = tostring(rid) }, nil)
      end)
    end)
  end

  attempt(false)
end

function M.record(rid, cb)
  http.json({ path = "/record/" .. tostring(rid), headers = LENTILLE, cookie = cookie() }, function(data, err)
    if err then
      return cb(nil, err)
    end
    if type(data) ~= "table" then
      return cb(nil, { msg = "记录响应为空" })
    end
    local status = tonumber(nn(data.status) or nn(data.code))
    if status and status >= 400 then
      local inner = nn(data.data)
      local msg = (type(inner) == "table" and nn(inner.errorMessage)) or nn(data.errorMessage) or ("HTTP " .. status)
      return cb(nil, { msg = msg, status = status })
    end
    local record = M.normalize_record(data)
    if not record then
      return cb(nil, { msg = "记录响应缺少数据（接口变更？）" })
    end
    cb(record, nil)
  end)
end

return M
