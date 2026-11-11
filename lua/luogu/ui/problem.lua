local M = {}

local api = require("luogu.api")
local config = require("luogu.config")
local langs = require("luogu.langs")
local render = require("luogu.render")

local LOG = vim.log.levels

local state = {
  by_pid = {}, -- pid -> code bufnr
  buffers = {}, -- code bufnr -> { pid, lang_key, lang, problem, desc_buf }
  desc_by_pid = {}, -- pid -> description bufnr
}

local function problem_path(pid, lang)
  return vim.fs.joinpath(config.data_dir(), "problems", pid .. "." .. lang.ext)
end

local function notify_err(msg)
  vim.notify(msg, LOG.ERROR)
end

local function set_desc_window_opts(win)
  vim.api.nvim_set_option_value("wrap", true, { win = win })
  vim.api.nvim_set_option_value("spell", false, { win = win })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = win })
  vim.api.nvim_set_option_value("concealcursor", "nc", { win = win })
  vim.api.nvim_set_option_value("number", false, { win = win })
  vim.api.nvim_set_option_value("relativenumber", false, { win = win })
end

local function set_code_keymaps(buf, pid)
  local keys = config.get().keys
  local function map(lhs, fn, desc)
    if not lhs or lhs == "" then
      return
    end
    vim.keymap.set("n", lhs, fn, { buffer = buf, desc = desc, nowait = true, silent = true })
  end

  map(keys.submit, function()
    M.submit()
  end, "Luogu: submit")
  map(keys.language, function()
    M.pick_language()
  end, "Luogu: pick language")
  map(keys.list, function()
    require("luogu.ui.list").open()
  end, "Luogu: problem list")
  map(keys.open_url, function()
    vim.ui.open("https://www.luogu.com.cn/problem/" .. pid)
  end, "Luogu: open in browser")
end

local function set_desc_keymaps(buf, pid)
  local keys = config.get().keys

  vim.keymap.set("n", "q", function()
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == buf then
        pcall(vim.api.nvim_win_close, win, true)
        return
      end
    end
  end, { buffer = buf, desc = "Luogu: close description", nowait = true, silent = true })

  if keys.submit and keys.submit ~= "" then
    vim.keymap.set("n", keys.submit, function()
      M.submit(pid)
    end, { buffer = buf, desc = "Luogu: submit", nowait = true, silent = true })
  end
end

local desc_ns = vim.api.nvim_create_namespace("luogu.desc")

local function paint_desc(buf, problem, tags)
  local doc = render.problem_document(problem, tags)
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, doc.lines)
  vim.api.nvim_buf_clear_namespace(buf, desc_ns, 0, -1)
  for _, mark in ipairs(doc.marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, desc_ns, mark.row, mark.start_col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end
  vim.bo[buf].modifiable = false
end

local function render_desc(buf, problem, tags)
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return
  end
  paint_desc(buf, problem, tags)
end

local function create_desc(problem, tags)
  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "markdown"
  vim.bo[buf].modifiable = true
  paint_desc(buf, problem, tags)
  vim.b[buf].luogu_pid = problem.pid
  vim.b[buf].luogu_desc = true
  return buf
end

local function code_buffer_for(pid)
  local buf = state.by_pid[pid]
  if buf and vim.api.nvim_buf_is_valid(buf) then
    return buf, state.buffers[buf]
  end
  return nil
end

local function show(problem)
  local pid = problem.pid
  if type(pid) ~= "string" or pid == "" then
    return notify_err("题目响应缺少 pid（接口变更？）")
  end
  local lang, lerr = langs.pick(problem)
  if not lang then
    return notify_err(lerr or "无法确定语言")
  end

  local path = problem_path(pid, lang)
  if vim.fn.isdirectory(path) == 1 then
    return notify_err("题目文件路径被目录占用：" .. path)
  end

  local fresh = vim.fn.filereadable(path) == 0
  if fresh then
    vim.fn.writefile({ "" }, path)
  end

  local code_buf = vim.fn.bufadd(path)
  vim.fn.bufload(code_buf)
  vim.bo[code_buf].buflisted = true
  vim.bo[code_buf].filetype = lang.ft
  vim.b[code_buf].luogu_pid = pid
  vim.b[code_buf].luogu_lang = lang.key

  if
    fresh
    and type(problem.last_code) == "string"
    and problem.last_code ~= ""
    and tonumber(problem.last_language) == lang.id
  then
    vim.api.nvim_buf_set_lines(code_buf, 0, -1, false, render.split_lines(problem.last_code))
    vim.api.nvim_buf_call(code_buf, function()
      pcall(vim.cmd, "silent write")
    end)
    vim.notify("已恢复上次提交的代码", LOG.INFO)
  end

  local tags = api.tags_cached()
  local desc_buf = create_desc(problem, tags and tags.by_id or nil)

  local cur_buf = vim.api.nvim_get_current_buf()
  local in_list = vim.b[cur_buf] and vim.b[cur_buf].luogu_list
  -- Splitting the only window of the only tab would make `:q` quit Neovim, so
  -- give the view its own tab in that case. Otherwise split where we are.
  if not in_list and #vim.api.nvim_tabpage_list_wins(0) == 1 and #vim.api.nvim_list_tabpages() == 1 then
    vim.cmd("tabnew")
  end

  local code_win = vim.api.nvim_get_current_win()
  vim.cmd("vsplit")
  local desc_win = vim.api.nvim_get_current_win()

  vim.api.nvim_win_set_buf(desc_win, desc_buf)
  vim.api.nvim_win_set_buf(code_win, code_buf)

  local width = math.min(vim.o.columns - 20, math.max(30, math.floor(vim.o.columns * 0.45)))
  pcall(vim.api.nvim_win_set_width, desc_win, width)
  set_desc_window_opts(desc_win)

  vim.api.nvim_set_current_win(code_win)

  set_code_keymaps(code_buf, pid)
  set_desc_keymaps(desc_buf, pid)

  state.by_pid[pid] = code_buf
  state.buffers[code_buf] = {
    pid = pid,
    lang_key = lang.key,
    lang = lang,
    problem = problem,
    desc_buf = desc_buf,
  }
  state.desc_by_pid[pid] = desc_buf

  vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
    buffer = code_buf,
    once = true,
    callback = function()
      state.buffers[code_buf] = nil
      if state.by_pid[pid] == code_buf then
        state.by_pid[pid] = nil
      end
    end,
  })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = desc_buf,
    once = true,
    callback = function()
      if state.desc_by_pid[pid] == desc_buf then
        state.desc_by_pid[pid] = nil
      end
    end,
  })

  if not tags then
    api.tags(function(loaded)
      if loaded then
        render_desc(desc_buf, problem, loaded.by_id)
      end
    end)
  end
end

---@param pid string
function M.open(pid)
  pid = tostring(pid or "")
  if not pid:match("^[%w_]+$") or #pid > 32 then
    return notify_err("非法题目 ID")
  end

  local existing = state.by_pid[pid]
  if existing and vim.api.nvim_buf_is_valid(existing) then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == existing then
        vim.api.nvim_set_current_win(win)
        return
      end
    end
    vim.cmd("tabnew")
    vim.api.nvim_win_set_buf(0, existing)
    return
  end

  vim.notify("正在加载 " .. pid .. "…", LOG.INFO)
  api.problem(pid, function(problem, err)
    if not problem then
      return notify_err(err and err.msg or "加载失败")
    end
    show(problem)
  end)
end

--- Resolve the code source for a submission.
---@param pid string|nil
---@return integer|nil bufnr, table|nil info, string|nil err
local function resolve_target(pid)
  if pid then
    pid = tostring(pid)
    local buf, info = code_buffer_for(pid)
    if buf then
      return buf, info, nil
    end
    local lang = langs.by_key[config.get().language]
    if not lang then
      return nil, nil, "未知语言：" .. tostring(config.get().language)
    end
    local path = problem_path(pid, lang)
    if vim.fn.filereadable(path) == 0 then
      return nil, nil, "请先 :Luogu open " .. pid
    end
    return nil, { pid = pid, lang = lang, lang_key = lang.key, path = path }, nil
  end

  local cur = vim.api.nvim_get_current_buf()
  if state.buffers[cur] then
    return cur, state.buffers[cur], nil
  end
  local buf_pid = vim.b[cur] and vim.b[cur].luogu_pid
  if buf_pid then
    local code_buf, info = code_buffer_for(buf_pid)
    if code_buf then
      return code_buf, info, nil
    end
  end
  return nil, nil, "当前缓冲区不是洛谷题目"
end

local function language_allowed(lang, accept)
  if not accept or next(accept) == nil then
    return true
  end
  for _, id in ipairs(accept) do
    if tonumber(id) == lang.id then
      return true
    end
  end
  return false
end

---@param pid string|nil
function M.submit(pid)
  local code_buf, info, err = resolve_target(pid)
  if err then
    return notify_err(err)
  end

  if not require("luogu.auth").require_login() then
    return
  end

  local code
  if code_buf then
    code = table.concat(vim.api.nvim_buf_get_lines(code_buf, 0, -1, false), "\n")
  else
    local ok, lines = pcall(vim.fn.readfile, info.path)
    if not ok then
      return notify_err("无法读取代码文件：" .. info.path)
    end
    code = table.concat(lines, "\n")
  end

  if code:match("^%s*$") then
    return notify_err("代码为空")
  end

  local lang = info.lang or langs.by_key[info.lang_key] or langs.by_key[config.get().language]
  if not lang then
    return notify_err("未知语言")
  end

  local problem = info.problem
  if problem and not language_allowed(lang, problem.accept_languages) then
    return notify_err("题目不接受当前语言：" .. lang.name)
  end

  local cfg = config.get()
  local o2 = cfg.o2 and lang.can_o2

  api.submit(info.pid, code, lang.id, o2, function(res, serr)
    if not res then
      return notify_err(serr and serr.msg or "提交失败")
    end
    vim.notify("已提交：rid " .. res.rid, LOG.INFO)
    require("luogu.ui.result").open(res.rid)
  end)
end

local function active_code_info()
  local cur = vim.api.nvim_get_current_buf()
  if state.buffers[cur] then
    return cur, state.buffers[cur]
  end
  local buf_pid = vim.b[cur] and vim.b[cur].luogu_pid
  if buf_pid then
    local code_buf, info = code_buffer_for(buf_pid)
    if code_buf then
      return code_buf, info
    end
  end
  return nil, nil
end

---@param key string|nil
function M.pick_language(key)
  local old_buf, info = active_code_info()
  if not info then
    return notify_err("当前缓冲区不是洛谷代码")
  end

  local accept = info.problem and info.problem.accept_languages
  local candidates = langs.for_problem(accept)

  local target_win = vim.api.nvim_get_current_win()
  if old_buf then
    for _, win in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(win) == old_buf then
        target_win = win
        break
      end
    end
  end

  local function choose(lang)
    if not lang then
      return
    end
    if not language_allowed(lang, accept) then
      return notify_err("题目不接受该语言：" .. lang.name)
    end

    local path = problem_path(info.pid, lang)
    if vim.fn.isdirectory(path) == 1 then
      return notify_err("题目文件路径被目录占用：" .. path)
    end
    if vim.fn.filereadable(path) == 0 then
      vim.fn.writefile({ "" }, path)
    end

    local buf = vim.fn.bufadd(path)
    vim.fn.bufload(buf)
    vim.bo[buf].buflisted = true
    vim.bo[buf].filetype = lang.ft
    vim.b[buf].luogu_pid = info.pid
    vim.b[buf].luogu_lang = lang.key

    pcall(vim.api.nvim_win_set_buf, target_win, buf)
    set_code_keymaps(buf, info.pid)

    state.buffers[buf] = {
      pid = info.pid,
      lang_key = lang.key,
      lang = lang,
      problem = info.problem,
      desc_buf = info.desc_buf,
    }
    state.by_pid[info.pid] = buf
    if old_buf then
      state.buffers[old_buf] = nil
    end

    vim.api.nvim_create_autocmd({ "BufDelete", "BufWipeout" }, {
      buffer = buf,
      once = true,
      callback = function()
        state.buffers[buf] = nil
        if state.by_pid[info.pid] == buf then
          state.by_pid[info.pid] = nil
        end
      end,
    })

    vim.notify("已切换语言：" .. lang.name, LOG.INFO)
  end

  if key then
    local lang = langs.by_key[key]
    if not lang then
      return notify_err("未知语言：" .. tostring(key))
    end
    return choose(lang)
  end

  vim.ui.select(candidates, {
    prompt = "选择语言",
    format_item = function(lang)
      local icon = require("luogu.ui.kit").devicon(lang.ext)
      return icon and (icon .. " " .. lang.name) or lang.name
    end,
  }, choose)
end

return M
