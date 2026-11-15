local client = require("luogu.client")
local lc = require("luogu.upstream").require
local Question = lc("leetcode-ui.question")
local Group = lc("leetcode-ui.group")
local config = lc("leetcode.config")
local log = lc("leetcode.logger")
local utils = lc("leetcode.utils")

local M = {}

local function append_lines(group, text)
    for _, line in ipairs(vim.split(tostring(text), "\n", { plain = true })) do
        group:append(line)
        group:endl()
    end
end

local function describe(description)
    local problem = description.question.luogu_problem
    local group = Group()
    for _, line in ipairs(require("luogu.markdown").document(problem)) do
        group:append(line)
        group:endl()
    end
    description.renderer:replace({ group })
end

local function show_result(console, text)
    if not (console.question.bufnr and vim.api.nvim_buf_is_valid(console.question.bufnr)) then
        return
    end
    local result = console.result
    local group = Group()
    append_lines(group, text)
    result.renderer:replace({ group })
    result:draw()
end

local function fetch_record(console, rid)
    client.record(rid, function(record, err)
        vim.schedule(function()
            if err then
                show_result(console, "获取评测记录失败: " .. err)
                return
            end
            if not record then
                show_result(console, "获取评测记录失败: 响应为空")
                return
            end
            show_result(console, "评测记录 " .. tostring(rid) .. "\n" .. vim.inspect(record))
            local status = tonumber(record.status)
            if status and status >= 0 and status <= 1
                and console.question.bufnr and vim.api.nvim_buf_is_valid(console.question.bufnr) then
                vim.defer_fn(function()
                    fetch_record(console, rid)
                end, 1500)
            end
        end)
    end)
end

local function run(console, submit)
    if not submit then
        log.warn("洛谷不支持远程运行自定义测试；请使用提交进行评测")
        return
    end
    local question = console.question
    local code = question:editor_submit_lines(true)
    console:show()
    console.result:focus()
    show_result(console, "正在提交…")
    client.submit(question.luogu_problem.pid, code, question.lang, function(data, err)
        vim.schedule(function()
            if err then
                show_result(console, "提交失败: " .. err)
            elseif not data or not data.rid then
                show_result(console, "提交失败: 响应中没有评测记录 ID")
            else
                show_result(console, "已提交，评测记录 " .. tostring(data.rid))
                fetch_record(console, data.rid)
            end
        end)
    end)
end

function M.open(pid)
    pid = tostring(pid)
    local tab = utils.detect_duplicate_question(pid, config.lang)
    if tab then
        vim.api.nvim_set_current_tabpage(tab)
        return
    end
    client.problem(pid, function(problem, err)
        vim.schedule(function()
            if err then
                log.error("获取题目失败: " .. err)
                return
            end
            if not problem then
                log.error("获取题目失败: 响应为空")
                return
            end
            local actual_pid = tostring(problem.pid or pid)
            problem.pid = actual_pid
            problem.name = problem.name or actual_pid
            local snippets = {}
            for _, lang in ipairs(config.langs) do
                snippets[#snippets + 1] = { lang_slug = lang.slug, lang = lang.lang, code = "" }
            end
            local cases = {}
            for _, sample in ipairs(problem.samples or {}) do
                cases[#cases + 1] = sample[1] or ""
            end
            local question = Question({ title_slug = actual_pid, link = "https://www.luogu.com.cn/problem/" .. actual_pid })
            question.luogu_problem = problem
            question.luogu_description = describe
            question.luogu_run = run
            question.q = {
                frontend_id = actual_pid,
                title_slug = actual_pid,
                title = problem.name,
                code_snippets = snippets,
                testcase_list = cases,
                meta_data = {},
                hints = {},
                similar = {},
                topic_tags = {},
            }
            question.injector = function(_, code)
                return code
            end
            question.editor_submit_lines = function(self)
                return table.concat(vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false), "\n")
            end
            local open_buffer = question.open_buffer
            question.open_buffer = function(self, existed)
                open_buffer(self, existed)
                local lines = vim.api.nvim_buf_get_lines(self.bufnr, 0, -1, false)
                local clean = vim.tbl_filter(function(line)
                    local marker = line:match("@leet.*start") or line:match("@leet.*end")
                    return not marker
                end, lines)
                if #clean ~= #lines then
                    vim.api.nvim_buf_set_lines(self.bufnr, 0, -1, false, clean)
                end
            end
            question:handle_mount()
        end)
    end)
end

return M
