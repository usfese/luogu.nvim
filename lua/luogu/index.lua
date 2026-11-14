local uv = vim.uv or vim.loop
local client = require("luogu.client")

local M = {}
local cache_dir = vim.fn.stdpath("cache") .. "/luogu"
local cache_path = cache_dir .. "/problem-index-v1.json"
local max_age = 24 * 60 * 60
local request_interval = 300
local notify_pages = 5

local state
local listeners = {}
local next_listener = 0
local syncing = false
local failure
local cache_failure
local requests = {}
local busy = false
local last_was_search = false

local function dispatch()
    if busy then return end
    local chosen
    for i, job in ipairs(requests) do
        if not job.cancelled and job.search and not last_was_search then
            chosen = i
            break
        end
    end
    if not chosen then
        for i, job in ipairs(requests) do
            if not job.cancelled and (not job.search or not chosen) then
                chosen = i
                if not job.search then break end
            end
        end
    end
    if not chosen then
        requests = {}
        return
    end
    local job = table.remove(requests, chosen)
    busy = true
    last_was_search = job.search
    local called = false
    local function done(data, err)
        if called then return end
        called = true
        if not job.cancelled then
            local ok, callback_err = pcall(job.callback, data, err)
            if not ok then vim.schedule(function() error(callback_err) end) end
        end
        vim.defer_fn(function()
            busy = false
            dispatch()
        end, request_interval)
    end
    local ok, err = pcall(client.list, job.opts, done)
    if not ok then done(nil, "洛谷请求失败: " .. tostring(err)) end
end

local function enqueue(opts, search, callback)
    local job = { opts = opts, search = search, callback = callback }
    requests[#requests + 1] = job
    dispatch()
    return function() job.cancelled = true end
end

local function valid_problems(problems)
    if type(problems) ~= "table" then return false end
    for _, problem in ipairs(problems) do
        if type(problem) ~= "table" or type(problem.pid) ~= "string" or problem.pid == "" then
            return false
        end
    end
    return true
end

local function load_cache()
    local stat, stat_err = uv.fs_stat(cache_path)
    if not stat then
        if stat_err and not tostring(stat_err):match("ENOENT") then
            cache_failure = "读取题库缓存失败: " .. tostring(stat_err)
        end
        return
    end
    local file, err = io.open(cache_path, "rb")
    if not file then
        cache_failure = "读取题库缓存失败: " .. tostring(err)
        return
    end
    local content = file:read("*a")
    file:close()
    local ok, data = pcall(vim.json.decode, content or "")
    if not ok or type(data) ~= "table" or data.version ~= 1
        or not valid_problems(data.problems) or not valid_problems(data.pending)
        or type(data.next_page) ~= "number" or data.next_page < 1 or data.next_page % 1 ~= 0
        or type(data.fetched) ~= "number" or data.fetched < 0
        or type(data.total) ~= "number" or data.total < 0
        or type(data.complete) ~= "boolean" or type(data.updated_at) ~= "number" then
        cache_failure = "题库缓存格式无效，已保留原文件: " .. cache_path
        return
    end
    state = data
end

local function save_cache()
    local ok, encoded = pcall(vim.json.encode, state)
    if not ok then return nil, tostring(encoded) end
    local mkdir_ok, mkdir_result = pcall(vim.fn.mkdir, cache_dir, "p")
    if not mkdir_ok or mkdir_result == 0 and not uv.fs_stat(cache_dir) then
        return nil, "无法创建缓存目录 " .. cache_dir
    end
    -- A unique temporary file and rename keep the previous checkpoint intact on failure.
    local temp, fd
    for _ = 1, 10 do
        temp = cache_path .. ".tmp." .. tostring(uv.hrtime())
        fd = uv.fs_open(temp, "wx", 384)
        if fd then break end
    end
    if not fd then return nil, "无法创建缓存临时文件" end
    local offset, write_err = 0, nil
    while offset < #encoded do
        local written, err = uv.fs_write(fd, encoded:sub(offset + 1), offset)
        if not written or written == 0 then
            write_err = err or "写入不完整"
            break
        end
        offset = offset + written
    end
    local closed, close_err = uv.fs_close(fd)
    if not closed and not write_err then write_err = close_err end
    if not write_err then
        local renamed, err = uv.fs_rename(temp, cache_path)
        if not renamed then write_err = err end
    end
    if write_err then
        uv.fs_unlink(temp)
        return nil, tostring(write_err)
    end
    return true
end

local function current_problems()
    if #state.problems == 0 then return state.pending end
    if #state.pending == 0 then return state.problems end
    local result, seen = {}, {}
    for _, problem in ipairs(state.problems) do
        result[#result + 1] = problem
        seen[problem.pid] = #result
    end
    for _, problem in ipairs(state.pending) do
        local index = seen[problem.pid]
        if index then
            result[index] = problem
        else
            result[#result + 1] = problem
            seen[problem.pid] = #result
        end
    end
    return result
end

local function notify_one(id)
    local problems = current_problems()
    local info = {
        loaded = state.complete and #state.problems or #state.pending,
        total = state.total,
        complete = state.complete,
        syncing = syncing,
        error = failure or cache_failure,
    }
    vim.schedule(function()
        local callback = listeners[id]
        if callback then callback(problems, info) end
    end)
end

local function notify_all()
    for id in pairs(listeners) do notify_one(id) end
end

local function stop(err)
    syncing = false
    failure = err
    notify_all()
end

local function fetch_page()
    local page = state.next_page
    enqueue({ page = page, type = "P" }, false, function(data, request_err)
        if request_err then return stop(tostring(request_err)) end
        if type(data) ~= "table" or not valid_problems(data.problems)
            or type(data.count) ~= "number" or data.count < 0 or data.count % 1 ~= 0 then
            return stop("洛谷题目列表响应无效")
        end
        if #data.problems == 0 and state.fetched < data.count then
            return stop("洛谷题目列表提前结束，索引未完成")
        end
        local seen = {}
        for _, problem in ipairs(state.pending) do seen[problem.pid] = true end
        for _, problem in ipairs(data.problems) do
            if not seen[problem.pid] then
                state.pending[#state.pending + 1] = problem
                seen[problem.pid] = true
            end
        end
        state.fetched = state.fetched + #data.problems
        state.total = data.count
        state.next_page = page + 1
        if state.fetched >= data.count then
            if #state.pending ~= data.count then
                -- Pagination shifted during indexing; restart rather than claim a complete index.
                state.problems = current_problems()
                state.next_page, state.fetched, state.pending = 1, 0, {}
                local saved, save_err = save_cache()
                return stop(saved and "洛谷题目列表发生变化，请重新同步" or "保存题库缓存失败: " .. tostring(save_err))
            end
            state.problems, state.pending = state.pending, {}
            state.complete = true
            state.updated_at = os.time()
        end
        local saved, save_err = save_cache()
        if not saved then return stop("保存题库缓存失败: " .. tostring(save_err)) end
        if state.complete then
            syncing = false
            notify_all()
        else
            if page == 1 or page % notify_pages == 0 then notify_all() end
            fetch_page()
        end
    end)
end

local function start_sync()
    if syncing or cache_failure then return end
    if failure and state.complete then
        local saved, err = save_cache()
        if not saved then
            failure = "保存题库缓存失败: " .. tostring(err)
            return
        end
        failure = nil
    end
    if state.complete and os.time() - state.updated_at < max_age then return end
    if state.complete then
        state.complete = false
        state.pending, state.next_page, state.fetched = {}, 1, 0
    end
    failure = nil
    syncing = true
    vim.schedule(fetch_page)
end

function M.search(keyword, callback)
    return enqueue({ page = 1, type = "P", keyword = keyword }, true, callback)
end

function M.open(on_update)
    assert(type(on_update) == "function", "on_update must be a function")
    if not state then
        load_cache()
        state = state or {
            version = 1,
            problems = {}, pending = {}, next_page = 1, fetched = 0,
            total = 0, complete = false, updated_at = 0,
        }
    end
    next_listener = next_listener + 1
    local id = next_listener
    listeners[id] = on_update
    start_sync()
    notify_one(id)
    return function() listeners[id] = nil end
end

return M
