local M = {}

local api = require("luogu.api")
local auth = require("luogu.auth")
local config = require("luogu.config")
local kit = require("luogu.ui.kit")
local status = require("luogu.status")

local LOG = vim.log.levels

local PID_W = 7
local DIFF_W = 13
local RATE_W = 6

local state = {
  buf = nil,
  win = nil,
  tab = nil,
  prev_tab = nil,
  back_buf = nil,
  view = "menu",
  page = 1,
  keyword = nil,
  difficulty = nil,
  all = nil,
  per_page = 50,
  updated_at = nil,
  syncing = false,
  sync_done = 0,
  sync_total = 0,
  partial = false,
  fetched_pages = nil,
  total_pages = nil,
  error = nil,
  tags = nil,
  tags_error = false,
  loading = false,
  row_map = {},
  ns = vim.api.nvim_create_namespace("luogu.menu"),
  auto_return = false,
}

local function tag_name(id)
  if state.tags and state.tags.by_id and state.tags.by_id[id] then
    return state.tags.by_id[id].name
  end
  return "#" .. tostring(id)
end

local function rate_text(p)
  local submit = tonumber(p.total_submit) or 0
  local accepted = tonumber(p.total_accepted) or 0
  return ("%.1f%%"):format(accepted / math.max(submit, 1) * 100)
end

local function popup_size()
  if state.view == "problems" then
    local width = math.min(120, math.max(64, vim.o.columns - 10))
    local height = math.min(34, math.max(16, math.floor(vim.o.lines * 0.8)))
    return width, height
  end
  local width = math.min(64, math.max(54, math.floor(vim.o.columns * 0.5)))
  local height = math.min(24, math.max(16, #kit.logo + 10))
  return width, height
end

local function place(win)
  local width, height = popup_size()
  pcall(vim.api.nvim_win_set_config, win, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Luogu ",
    title_pos = "center",
    zindex = 40,
  })
end

local function ensure_tab()
  if state.tab and vim.api.nvim_tabpage_is_valid(state.tab) then
    if vim.api.nvim_get_current_tabpage() ~= state.tab then
      pcall(vim.api.nvim_set_current_tabpage, state.tab)
    end
    return
  end

  state.prev_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")
  state.tab = vim.api.nvim_get_current_tabpage()

  local buf = vim.api.nvim_get_current_buf()
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "hide"
  vim.bo[buf].swapfile = false
  vim.bo[buf].buflisted = false
  state.back_buf = buf
end

local function back_window()
  if not (state.tab and vim.api.nvim_tabpage_is_valid(state.tab)) then
    return nil
  end
  for _, win in ipairs(vim.api.nvim_tabpage_list_wins(state.tab)) do
    if vim.api.nvim_win_get_buf(win) == state.back_buf then
      return win
    end
  end
  return nil
end

local function activate()
  local row = state.row_map[vim.fn.line(".") - 1]
  if not row then
    return
  end
  row.action()
end

local function set_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  map("<CR>", activate, "Luogu: select")
  map("q", function()
    M.back()
  end, "Luogu: back")

  map("p", function()
    if state.view == "menu" then
      M.open("problems")
    else
      M.goto_page(state.page - 1)
    end
  end, "Luogu: problems / previous page")

  map("h", function()
    if state.view == "problems" then
      M.goto_page(state.page - 1)
    end
  end, "Luogu: previous page")

  map("l", function()
    if state.view == "menu" then
      if auth.get_cookie() ~= "" then
        auth.logout()
      else
        auth.login()
      end
      M.render()
    else
      M.goto_page(state.page + 1)
    end
  end, "Luogu: sign in or out / next page")

  map("g", function()
    if state.view ~= "problems" then
      return
    end
    local pages = M.page_count()
    vim.ui.input({ prompt = ("跳到第几页 (1-%d): "):format(pages) }, function(input)
      if not input or input == "" then
        return
      end
      M.goto_page(input)
    end)
  end, "Luogu: go to page")

  map("r", function()
    if state.view == "problems" then
      M.refresh()
    end
  end, "Luogu: refresh")

  map("/", function()
    if state.view ~= "problems" then
      return
    end
    local keyword = vim.fn.input("搜索: ", state.keyword or "")
    state.keyword = keyword ~= "" and keyword or nil
    state.page = 1
    M.render()
  end, "Luogu: search")

  map("d", function()
    if state.view ~= "problems" then
      return
    end
    local items = { { label = "全部", value = nil } }
    for id = 0, 8 do
      items[#items + 1] = { label = status.difficulty(id), value = id }
    end
    vim.ui.select(items, {
      prompt = "难度",
      format_item = function(item)
        return item.label
      end,
    }, function(choice)
      if not choice then
        return
      end
      state.difficulty = choice.value
      state.page = 1
      M.render()
    end)
  end, "Luogu: difficulty")

  map("n", function()
    if state.view == "problems" then
      M.goto_page(state.page + 1)
    end
  end, "Luogu: next page")
end

local function ensure_popup()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    place(state.win)
    return
  end

  if not (state.buf and vim.api.nvim_buf_is_valid(state.buf)) then
    state.buf = vim.api.nvim_create_buf(false, true)
    vim.bo[state.buf].bufhidden = "hide"
    vim.bo[state.buf].swapfile = false
    vim.bo[state.buf].filetype = "luogu-menu"
    vim.bo[state.buf].modifiable = false
    set_keymaps(state.buf)
  end

  local width, height = popup_size()
  state.win = vim.api.nvim_open_win(state.buf, true, {
    relative = "editor",
    width = width,
    height = height,
    row = math.max(0, math.floor((vim.o.lines - height) / 2) - 1),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Luogu ",
    title_pos = "center",
    zindex = 40,
  })
  vim.wo[state.win].cursorline = true
  vim.wo[state.win].wrap = false
  vim.wo[state.win].number = false
  vim.wo[state.win].relativenumber = false
end

local function breadcrumb(tail)
  local line = kit.line():add("Menu", tail == "Menu" and "LuoguTitle" or "LuoguMuted")
  if tail ~= "Menu" then
    line:add(" " .. kit.icons.caret .. " ", "LuoguMuted")
    line:add(tail, "LuoguTitle")
  end
  return line
end

local function login_line()
  local signed_in = auth.get_cookie() ~= ""
  local line = kit.line():add(kit.bar .. " ", "LuoguMuted")
  if signed_in then
    line:add(kit.icons.ac .. " 已登录", "LuoguOk")
  else
    line:add(kit.icons.todo .. " 未登录", "LuoguMuted")
  end
  return line
end

local function build_problem_row(problem, name_w, tag_w)
  local line = kit.line()

  local pid = tostring(problem.pid or "?")
  line:add(pid, "LuoguPid")
  line:add((" "):rep(math.max(1, PID_W - #pid)))

  line:add(kit.pad(kit.fit(problem.name or "", name_w), name_w))
  line:add(" ")

  local diff = kit.fit(status.difficulty(problem.difficulty), DIFF_W)
  line:add(diff, status.difficulty_hl(problem.difficulty))
  line:add((" "):rep(math.max(0, DIFF_W - kit.width(diff))))
  line:add(" ")

  line:add(kit.right(rate_text(problem), RATE_W), "LuoguAlt")

  local names = {}
  for _, id in ipairs(problem.tags or {}) do
    if #names >= 2 then
      break
    end
    names[#names + 1] = tag_name(id)
  end
  local tags = kit.fit(table.concat(names, ", "), tag_w)
  if tags ~= "" then
    line:add("  ")
    line:add(tags, "LuoguMuted")
  end

  return line
end

local function render_menu(push, push_text, width)
  for _, logo_line in ipairs(kit.logo) do
    push(kit.line():add(logo_line, "LuoguLogo"))
  end
  push_text("")
  push(breadcrumb("Menu"))
  push_text("")

  local signed_in = auth.get_cookie() ~= ""
  local items = {
    { label = "Problems", key = "p", action = function() end },
    {
      label = signed_in and "Sign out" or "Sign in",
      key = "l",
      action = function() end,
    },
    { label = "Close", key = "q", action = function() M.close() end },
  }
  items[1].action = function()
    M.open("problems")
  end
  items[2].action = function()
    if signed_in then
      auth.logout()
    else
      auth.login()
    end
    M.render()
  end

  for _, item in ipairs(items) do
    local line = kit.line()
    line:add("  " .. kit.icons.caret .. " ", "LuoguMuted")
    line:add(item.label, "LuoguAlt")
    line:pad_to(width - 3)
    line:add(item.key, "LuoguKey")
    local row = push(line)
    state.row_map[row] = { kind = "menu", action = item.action }
  end

  push_text("")
  push(login_line())
end

local function filtered_problems()
  local out = {}
  local keyword = state.keyword and state.keyword ~= "" and state.keyword:lower() or nil
  for _, problem in ipairs(state.all or {}) do
    local keep = true
    if keyword then
      local name = tostring(problem.name or ""):lower()
      local pid = tostring(problem.pid or ""):lower()
      keep = name:find(keyword, 1, true) ~= nil or pid:find(keyword, 1, true) ~= nil
    end
    if keep and state.difficulty ~= nil then
      keep = tonumber(problem.difficulty) == state.difficulty
    end
    if keep then
      out[#out + 1] = problem
    end
  end
  return out
end

local function page_count_for(list)
  return math.max(1, math.ceil(#list / math.max(state.per_page, 1)))
end

local function render_problems(push, push_text, width)
  local list = filtered_problems()
  local pages = page_count_for(list)
  if state.page > pages then
    state.page = pages
  end

  local first = (state.page - 1) * state.per_page + 1
  local last = math.min(#list, first + state.per_page - 1)
  local slice = {}
  for i = first, last do
    slice[#slice + 1] = list[i]
  end

  push(breadcrumb("Problems"))
  push_text("")

  local diff_label = state.difficulty ~= nil and status.difficulty(state.difficulty) or "全部"
  local keyword = state.keyword and state.keyword ~= "" and state.keyword or "无"
  local stats = kit.line()
  stats:add(kit.bar .. " ", "LuoguMuted")
  stats:add("难度 " .. diff_label, "LuoguAlt")
  stats:add(" " .. kit.bar .. " ", "LuoguMuted")
  stats:add("搜索 " .. keyword, "LuoguAlt")
  stats:add(" " .. kit.bar .. " ", "LuoguMuted")
  stats:add(("第 %d/%d 页"):format(state.page, pages), "LuoguAlt")
  if state.syncing then
    stats:add(" " .. kit.bar .. " ", "LuoguMuted")
    stats:add(("同步 %d/%d"):format(state.sync_done, state.sync_total), "LuoguPending")
  end
  push(stats)
  push_text("")

  local name_w = math.max(18, math.min(44, width - PID_W - DIFF_W - RATE_W - 16))
  local tag_w = math.max(8, math.min(24, width - PID_W - name_w - DIFF_W - RATE_W - 4))

  if state.error then
    push(kit.line():add(state.error, "LuoguError"))
    push_text("")
  end

  if not state.all then
    local text = state.syncing and ("正在同步题库 %d/%d…"):format(state.sync_done, state.sync_total)
      or "还没有题库缓存，按 r 重试"
    push(kit.line():add(text, "LuoguMuted"))
  elseif #list == 0 then
    push(kit.line():add("没有找到题目", "LuoguMuted"))
  else
    for _, problem in ipairs(slice) do
      local row = push(build_problem_row(problem, name_w, tag_w))
      state.row_map[row] = {
        kind = "problem",
        action = function()
          M.open_problem(problem.pid)
        end,
      }
    end
  end

  push_text("")
  local footer = kit.line()
  footer:add(kit.bar .. " ", "LuoguMuted")
  footer:add(("%d 题"):format(#(state.all or {})), "LuoguAlt")
  if #list ~= #(state.all or {}) then
    footer:add((" %s 筛选 %d"):format(kit.bar, #list), "LuoguAlt")
  end
  footer:add((" %s 本页 %d"):format(kit.bar, #slice), "LuoguAlt")
  if state.partial then
    footer:add(
      (" %s 未完整 %s/%s 页"):format(kit.bar, tostring(state.fetched_pages or "?"), tostring(state.total_pages or "?")),
      "LuoguWarn"
    )
  end
  if state.updated_at then
    footer:add((" %s %s"):format(kit.bar, os.date("%m-%d %H:%M", state.updated_at)), "LuoguMuted")
  end
  push(footer)

  local hints = kit.line()
  local function hint(key, desc)
    if hints.text ~= "" then
      hints:add("   ")
    end
    hints:add(key, "LuoguKey")
    hints:add(" " .. desc, "LuoguMuted")
  end
  hint("q", "返回")
  hint("<CR>", "打开")
  hint("h/l", "翻页")
  hint("g", "跳页")
  hint("/", "搜索")
  hint("d", "难度")
  hint("r", "刷新")
  push(hints)
end

function M.render()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {}
  local marks = {}

  local function push(line)
    local row = #lines
    lines[row + 1] = line.text
    for _, mark in ipairs(line.marks) do
      marks[#marks + 1] = { row = row, start_col = mark.start_col, end_col = mark.end_col, hl = mark.hl }
    end
    return row
  end

  local function push_text(text)
    push(kit.line():add(text))
  end

  local width = 80
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    width = vim.api.nvim_win_get_width(state.win)
  end

  state.row_map = {}
  local first_row = nil

  if state.view == "problems" then
    render_problems(push, push_text, width)
  else
    render_menu(push, push_text, width)
  end

  for row in pairs(state.row_map) do
    if not first_row or row < first_row then
      first_row = row
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  for _, mark in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, mark.row, mark.start_col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end
  vim.bo[buf].modifiable = false

  if first_row and state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_set_cursor, state.win, { first_row + 1, 0 })
  end
end

local cache = require("luogu.cache")

local function adopt(data)
  state.all = data.problems
  state.per_page = data.per_page or 50
  state.updated_at = data.updated_at
  state.partial = data.partial == true
  state.fetched_pages = data.fetched_pages
  state.total_pages = data.total_pages
  state.error = nil
end

function M.page_count()
  return page_count_for(filtered_problems())
end

function M.goto_page(n)
  local pages = M.page_count()
  state.page = math.max(1, math.min(pages, tonumber(n) or 1))
  M.render()
end

function M.sync()
  if state.syncing then
    return
  end
  state.syncing = true
  state.sync_done, state.sync_total = 0, 0
  M.render()

  cache.sync({
    type = config.get().problem_type,
    on_progress = function(done, total)
      state.sync_done, state.sync_total = done, total
      if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
        M.render()
      end
    end,
  }, function(data, err)
    state.syncing = false
    if data then
      adopt(data)
    end
    if err then
      local extra = ""
      if data and data.partial then
        extra = ("（已缓存 %d/%d 页，按 r 继续）"):format(data.fetched_pages, data.total_pages)
      end
      state.error = "题库同步中断：" .. (err.msg or "未知错误") .. extra
      return M.render()
    end
    state.page = 1
    M.render()
    vim.notify(("题库缓存已更新：%d 题"):format(#data.problems), LOG.INFO)
  end)
end

function M.refresh()
  local data = cache.load()
  if data then
    adopt(data)
    M.render()
    if cache.stale(data) then
      M.sync()
    end
  else
    M.sync()
  end
end

local function ensure_loaded()
  if state.all then
    return
  end
  local data = cache.load()
  if data then
    adopt(data)
    if cache.stale(data) then
      M.sync()
    end
  else
    M.sync()
  end
end

local function ensure_tags()
  if state.tags or state.tags_error then
    return
  end
  api.tags(function(tags, err)
    if not tags then
      state.tags_error = true
      vim.notify("标签加载失败：" .. (err and err.msg or "未知错误"), LOG.WARN)
      return
    end
    state.tags = tags
    if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
      M.render()
    end
  end)
end

function M.open(view)
  state.view = view or state.view or "menu"
  ensure_tab()
  ensure_popup()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    place(state.win)
  end
  M.render()

  if state.view == "problems" then
    ensure_tags()
    ensure_loaded()
    M.render()
  end
end

--- Hide the menu so a problem can use this tab. Returns a restore function.
function M.hide_for_problem()
  state.auto_return = true
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    pcall(vim.api.nvim_win_close, state.win, true)
  end
  state.win = nil

  local win = back_window()
  if win then
    pcall(vim.api.nvim_set_current_win, win)
  end

  return function()
    M.reopen()
  end
end

function M.reopen()
  state.auto_return = false
  ensure_tab()
  ensure_popup()
  M.render()
  if state.view == "problems" then
    ensure_loaded()
  end
end

function M.open_problem(pid)
  local restore = M.hide_for_problem()
  require("luogu.ui.problem").open(pid, { on_error = restore })
end

function M.back()
  if state.view == "problems" then
    state.view = "menu"
    M.render()
    return
  end
  M.close()
end

function M.close()
  state.auto_return = false
  local win, buf, tab, prev = state.win, state.buf, state.tab, state.prev_tab

  state.win = nil
  state.buf = nil
  state.tab = nil
  state.prev_tab = nil
  state.back_buf = nil

  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  if tab and vim.api.nvim_tabpage_is_valid(tab) then
    local wins = vim.api.nvim_tabpage_list_wins(tab)
    if #wins == 1 and #vim.api.nvim_list_tabpages() > 1 then
      pcall(vim.api.nvim_set_current_tabpage, tab)
      pcall(vim.cmd, "tabclose")
    elseif #wins == 1 then
      pcall(vim.cmd, "enew")
    end
  end

  if prev and vim.api.nvim_tabpage_is_valid(prev) then
    pcall(vim.api.nvim_set_current_tabpage, prev)
  end
end

function M.should_return()
  return state.auto_return and state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

function M.current_tab()
  return state.tab ~= nil and vim.api.nvim_tabpage_is_valid(state.tab) and vim.api.nvim_get_current_tabpage() == state.tab
end

---@return table|nil
function M.get_data()
  return { result = state.all or {} }
end

M.state = state

return M
