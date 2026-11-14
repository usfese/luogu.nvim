local curl = require("plenary.curl")
local uv = vim.uv or vim.loop

local M = {}
local base = "https://www.luogu.com.cn"
local cookie_path = vim.fn.stdpath("data") .. "/luogu/cookie"
local cookie
local loaded = false

local languages = {
    pascal = 1, c = 2, cpp = 28, ["c++"] = 28, cpp98 = 3, cpp11 = 4,
    cpp14 = 28, cpp17 = 12, cpp20 = 27, cpp23 = 34,
    python = 7, python3 = 7, python2 = 6, pypy = 25, pypy3 = 25, pypy2 = 24,
    java = 8, java8 = 8, java21 = 33, rust = 15, go = 14, golang = 14,
    haskell = 19, ocaml = 30, julia = 31, lua = 32, kotlin = 21,
    scala = 22, csharp = 17, ["c#"] = 17, javascript = 9, node = 9,
    php = 16, ruby = 13, perl = 23, shell = 10,
}

local function load_cookie()
    if not loaded then
        loaded = true
        local fd = io.open(cookie_path, "r")
        if fd then
            cookie = fd:read("*a")
            fd:close()
            if cookie == "" then cookie = nil end
        end
    end
    return cookie
end

local function save_cookie(value)
    local dir = vim.fn.fnamemodify(cookie_path, ":h")
    vim.fn.mkdir(dir, "p", 448)
    local fd, err = uv.fs_open(cookie_path, "w", 384)
    if not fd then return nil, err end
    local ok, chmod_err = uv.fs_fchmod(fd, 384)
    if not ok then uv.fs_close(fd); return nil, chmod_err end
    local written, write_err = uv.fs_write(fd, value, 0)
    uv.fs_close(fd)
    if not written or written ~= #value then return nil, write_err or "incomplete cookie write" end
    return true
end

local function encode(value)
    return (tostring(value):gsub("([^%w%-_%.~])", function(c)
        return string.format("%%%02X", string.byte(c))
    end))
end

local function decode(body)
    local json = body:match('<script[^>]-id=["\']lentille%-context["\'][^>]*>(.-)</script>') or body
    local ok, data = pcall(vim.json.decode, json)
    if not ok or type(data) ~= "table" then return nil, "洛谷响应不是有效的 JSON 或页面数据" end
    if data.errorMessage then return nil, tostring(data.errorMessage) end
    if type(data.code) == "number" and data.code ~= 200 then
        return nil, tostring(data.message or data.msg or data.error or data.data or ("洛谷错误 " .. data.code))
    end
    if type(data.status) == "number" and data.status >= 400 then
        return nil, tostring(data.message or data.msg or data.error
            or (type(data.data) == "table" and data.data.errorMessage) or ("洛谷错误 " .. data.status))
    end
    return data
end

local function request(method, path, opts, cb)
    opts = opts or {}
    local headers = {
        ["User-Agent"] = "luogu.nvim/1.0",
        ["Referer"] = base .. "/",
        ["X-Requested-With"] = "XMLHttpRequest",
    }
    local session = opts.cookie or load_cookie()
    if session and session ~= "" then headers.Cookie = session end
    if opts.lentille then headers["X-Lentille-Request"] = "content-only" end
    if opts.csrf then headers["X-CSRF-Token"] = opts.csrf end
    if opts.body then headers["Content-Type"] = "application/json" end
    local args = {
        headers = headers,
        body = opts.body and vim.json.encode(opts.body) or nil,
        timeout = 30000,
        callback = vim.schedule_wrap(function(res)
            if not res then return cb(nil, "洛谷请求失败") end
            if not res.status or res.status < 200 or res.status >= 300 then
                local data, decode_err
                if res.body then data, decode_err = decode(res.body) end
                local message = (data and (data.errorMessage or data.message or data.msg)) or decode_err
                return cb(nil, "洛谷 HTTP " .. tostring(res.status or "错误") .. (message and (": " .. tostring(message)) or ""))
            end
            if opts.raw then return cb(res.body) end
            local data, err = decode(res.body or "")
            cb(data, err)
        end),
        on_error = vim.schedule_wrap(function(err)
            local message = type(err) == "table" and (err.message or err.stderr) or err
            cb(nil, "洛谷请求失败: " .. tostring(message))
        end),
    }
    local ok, err = pcall(curl[method], base .. path, args)
    if not ok then vim.schedule(function() cb(nil, "洛谷请求失败: " .. tostring(err)) end) end
end

local function response_data(data)
    return data and (data.data or data.currentData) or nil
end

function M.login(value, cb)
    if type(value) ~= "string" or value:match("^%s*$") or value:find("[\r\n]") then
        return cb(nil, "请输入浏览器 Cookie 请求头的内容")
    end
    value = value:gsub("^%s*[Cc]ookie:%s*", ""):gsub("^%s+", ""):gsub("%s+$", "")
    request("get", "/record/list", { cookie = value, lentille = true }, function(data, err)
        if err then return cb(nil, err) end
        local user = data.user or data.currentUser
        if type(user) ~= "table" or not user.uid then
            return cb(nil, "Cookie 未登录或已失效，请从浏览器复制完整 Cookie")
        end
        local ok, save_err = save_cookie(value)
        if not ok then return cb(nil, "保存 Cookie 失败: " .. tostring(save_err)) end
        cookie, loaded = value, true
        cb(user)
    end)
end

function M.logout()
    cookie, loaded = nil, true
    local ok, err = uv.fs_unlink(cookie_path)
    if not ok and err and not tostring(err):match("ENOENT") then return nil, tostring(err) end
    return true
end

function M.list(opts, cb)
    opts = opts or {}
    local query = {}
    for _, key in ipairs({ "page", "keyword", "difficulty", "type", "tag", "order", "orderBy", "content" }) do
        if opts[key] ~= nil then query[#query + 1] = encode(key) .. "=" .. encode(opts[key]) end
    end
    local path = "/problem/list" .. (#query > 0 and ("?" .. table.concat(query, "&")) or "")
    request("get", path, { lentille = true }, function(data, err)
        if err then return cb(nil, err) end
        local result = response_data(data)
        local list = result and result.problems
        if type(list) ~= "table" or type(list.result) ~= "table" or type(list.count) ~= "number" then
            return cb(nil, "洛谷题目列表响应缺少数据")
        end
        for _, problem in ipairs(list.result) do
            problem.name = problem.name or problem.title
        end
        cb({ problems = list.result, count = list.count })
    end)
end

function M.problem(pid, cb)
    if type(pid) ~= "string" or pid == "" then return cb(nil, "题号不能为空") end
    request("get", "/problem/" .. encode(pid), { lentille = true }, function(data, err)
        if err then return cb(nil, err) end
        local result = response_data(data)
        local p = result and result.problem
        if type(p) ~= "table" or not p.pid then return cb(nil, "洛谷题目响应缺少数据") end
        p.name = p.name or p.title
        p.content = p.content or p.contenu
        p.accept_languages = p.acceptLanguages or p.languages
        cb(p)
    end)
end

function M.submit(pid, code, lang, cb)
    if not load_cookie() then return cb(nil, "请先使用 Cookie 登录洛谷") end
    if type(pid) ~= "string" or pid == "" or type(code) ~= "string" then return cb(nil, "题号或代码无效") end
    local id = tonumber(lang) or (type(lang) == "string" and languages[lang:lower()])
    if not id then return cb(nil, "不支持的提交语言: " .. tostring(lang)) end
    local path = "/problem/" .. encode(pid)
    request("get", path, { raw = true }, function(html, err)
        if err then return cb(nil, err) end
        local token = html:match('<meta%s+name=["\']csrf%-token["\']%s+content=["\']([^"\']+)')
        if not token then return cb(nil, "无法从题目页面获取 CSRF 令牌，可能需要登录或验证") end
        request("post", "/fe/api/problem/submit/" .. encode(pid), {
            csrf = token, body = { code = code, lang = id, enableO2 = 0 },
        }, function(data, post_err)
            if post_err then return cb(nil, post_err) end
            if not data.rid then return cb(nil, tostring(data.errorMessage or data.message or data.msg or data.data or "提交响应缺少记录编号，可能需要验证码")) end
            cb(data)
        end)
    end)
end

function M.record(rid, cb)
    if not tostring(rid or ""):match("^%d+$") then return cb(nil, "评测记录编号无效") end
    request("get", "/record/" .. encode(rid) .. "?_contentOnly=1", {}, function(data, err)
        if err then return cb(nil, err) end
        local result = response_data(data)
        if type(result) ~= "table" or type(result.record) ~= "table" then
            return cb(nil, "洛谷评测记录响应缺少数据")
        end
        cb(result.record)
    end)
end

return M
