local M = {}

local function notify_error(err)
    vim.notify(tostring(err), vim.log.levels.ERROR, { title = "洛谷" })
end

local difficulties = {
    [0] = "暂无评定",
    [1] = "入门",
    [2] = "普及−",
    [3] = "普及/提高−",
    [4] = "普及+/提高",
    [5] = "提高+/省选−",
    [6] = "省选/NOI−",
    [7] = "NOI/NOI+/CTSC",
}

local function entry_maker(problem)
    local difficulty = difficulties[problem.difficulty] or problem.difficulty or "未知"
    local accepted = tonumber(problem.totalAccepted)
    local submitted = tonumber(problem.totalSubmit)
    local rate = submitted and submitted > 0 and accepted and ("%.1f%%"):format(accepted * 100 / submitted) or "—"
    local pid, name = tostring(problem.pid), tostring(problem.name or problem.title or "")
    return {
        value = problem,
        display = ("%s  %s  [%s]  %s"):format(pid, name, tostring(difficulty), rate),
        ordinal = pid .. " " .. name,
    }
end

function M.open()
    local pickers = require("telescope.pickers")
    local finders = require("telescope.finders")
    local conf = require("telescope.config").values
    local actions = require("telescope.actions")
    local action_state = require("telescope.actions.state")
    local theme = require("telescope.themes").get_dropdown({
        previewer = false,
        layout_config = { width = 0.9, height = 0.8 },
    })
    local index = require("luogu.index")

    local indexed, remote, entries = {}, {}, {}
    local info = { loaded = 0, syncing = true }
    local prompt, generation, last_error = "", 0, nil
    local picker, unsubscribe, cancel_search
    local closed = false

    local function finder()
        local results, seen = {}, {}
        for _, source in ipairs({ indexed, remote }) do
            for _, problem in ipairs(source) do
                local pid = tostring(problem.pid)
                if not seen[pid] then
                    seen[pid] = true
                    local entry = entries[pid]
                    if not entry then
                        entry = entry_maker(problem)
                        entries[pid] = entry
                    end
                    results[#results + 1] = entry
                end
            end
        end
        return finders.new_table({ results = results, entry_maker = function(entry) return entry end })
    end

    local function refresh()
        if closed or not picker or not picker.prompt_bufnr or not vim.api.nvim_buf_is_valid(picker.prompt_bufnr) then
            return
        end
        local count = tostring(info.loaded or #indexed)
        if info.total then count = count .. "/" .. tostring(info.total) end
        local status = info.complete and "已完成" or (info.error and "同步失败" or (info.syncing and "同步中" or "未完成"))
        picker.results_border:change_title(("题库 %s · %s"):format(count, status))
        picker:refresh(finder(), { reset_prompt = false })
    end

    local function search_remote(keyword)
        generation = generation + 1
        local request_id = generation
        if cancel_search then
            cancel_search()
            cancel_search = nil
        end
        remote = {}
        if info.complete or keyword:match("^%s*$") then return end
        vim.defer_fn(function()
            if closed or request_id ~= generation or info.complete then return end
            cancel_search = index.search(keyword, function(data, err)
                vim.schedule(function()
                    if closed or request_id ~= generation or info.complete then return end
                    if err then
                        notify_error(err)
                        return
                    end
                    remote = data and data.problems or {}
                    refresh()
                end)
            end)
        end, 350)
    end

    picker = pickers.new(theme, {
        prompt_title = "搜索洛谷题库",
        finder = finder(),
        sorter = conf.generic_sorter(theme),
        selection_strategy = "follow",
        on_input_filter_cb = function(value)
            if value ~= prompt then
                prompt = value
                search_remote(value)
                return { updated_finder = finder() }
            end
        end,
        attach_mappings = function(prompt_bufnr)
            vim.api.nvim_create_autocmd("BufWipeout", {
                buffer = prompt_bufnr,
                once = true,
                callback = function()
                    closed = true
                    generation = generation + 1
                    if cancel_search then cancel_search() end
                    if unsubscribe then unsubscribe() end
                end,
            })
            actions.select_default:replace(function()
                local selected = action_state.get_selected_entry()
                if not selected then return end
                actions.close(prompt_bufnr)
                require("luogu.question").open(selected.value.pid)
            end)
            return true
        end,
    })
    picker:find()
    unsubscribe = index.open(function(problems, state)
        if closed then return end
        indexed, info = problems, state
        if info.error and info.error ~= last_error then notify_error(info.error) end
        last_error = info.error
        if info.complete then
            generation = generation + 1
            if cancel_search then
                cancel_search()
                cancel_search = nil
            end
            remote = {}
        end
        refresh()
    end)
    if closed then unsubscribe() end
end

function M.cookie_prompt()
    local previous = vim.fn.histnr("input")
    local cookie = vim.fn.input("洛谷 Cookie：")
    local current = vim.fn.histnr("input")
    if current > previous and vim.fn.histget("input", current) == cookie then
        vim.fn.histdel("input", current)
    end
    if cookie == "" then
        return
    end
    require("luogu.client").login(cookie, function(_, err)
        vim.schedule(function()
            if err then
                notify_error(err)
            else
                vim.notify("洛谷登录成功", vim.log.levels.INFO, { title = "洛谷" })
            end
        end)
    end)
end

return M
