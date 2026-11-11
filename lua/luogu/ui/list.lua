local M = {}

local api = require("luogu.api")
local config = require("luogu.config")
local status = require("luogu.status")
local kit = require("luogu.ui.kit")

local LOG = vim.log.levels

local PID_W = 7
local DIFF_W = 13
local RATE_W = 6

local state = {
  buf = nil,
  win = nil,
  prev_tab = nil,
  page = 1,
  keyword = nil,
  difficulty = nil,
  data = nil,
  error = nil,
  tags = nil,
  tags_error = false,
  loading = false,
  row_to_problem = {},
  ns = vim.api.nvim_create_namespace("luogu.list"),
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

local function layout_width()
  if state.win and vim.api.nvim_win_is_valid(state.win) then
    return vim.api.nvim_win_get_width(state.win)
  end
  return vim.o.columns
end

--- Build one list row plus its highlight marks (byte columns).
---@param problem table
---@param name_w integer
---@param tag_w integer
---@return table kit line
local function build_row(problem, name_w, tag_w)
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

function M.render()
  local buf = state.buf
  if not buf or not vim.api.nvim_buf_is_valid(buf) then
    return
  end

  local lines = {}
  local marks = {}
  local data = state.data
  local count = data and data.count or 0
  local per_page = math.max(data and data.perPage or 50, 1)
  local pages = math.max(1, math.ceil(count / per_page))
  local width = layout_width()

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

  for _, logo_line in ipairs(kit.logo) do
    push(kit.line():add(logo_line, "LuoguLogo"))
  end
  push_text("")

  push(
    kit
      .line()
      :add("Menu", "LuoguMuted")
      :add(" " .. kit.icons.caret .. " ", "LuoguMuted")
      :add("Problems", "LuoguTitle")
  )
  push_text("")

  local diff_label = state.difficulty ~= nil and status.difficulty(state.difficulty) or "全部"
  local keyword = state.keyword and state.keyword ~= "" and state.keyword or "无"
  local signed_in = require("luogu.auth").get_cookie() ~= ""

  local stats = kit.line()
  stats:add(kit.bar .. " ", "LuoguMuted")
  stats:add("难度 " .. diff_label, "LuoguAlt")
  stats:add(" " .. kit.bar .. " ", "LuoguMuted")
  stats:add("搜索 " .. keyword, "LuoguAlt")
  stats:add(" " .. kit.bar .. " ", "LuoguMuted")
  if signed_in then
    stats:add(kit.icons.ac .. " 已登录", "LuoguOk")
  else
    stats:add(kit.icons.todo .. " 未登录", "LuoguMuted")
  end
  push(stats)
  push_text("")

  state.row_to_problem = {}
  local first_row = nil
  local name_w = math.max(18, math.min(44, width - PID_W - DIFF_W - RATE_W - 26))
  local tag_w = math.max(8, math.min(24, width - PID_W - name_w - DIFF_W - RATE_W - 12))

  if state.error then
    push(kit.line():add("加载失败：" .. state.error, "LuoguError"))
  elseif not data then
    push(kit.line():add("加载中…", "LuoguMuted"))
  elseif #data.result == 0 then
    push(kit.line():add("没有找到题目", "LuoguMuted"))
  else
    for _, problem in ipairs(data.result) do
      local row = push(build_row(problem, name_w, tag_w))
      if not first_row then
        first_row = row
      end
      state.row_to_problem[row] = problem
    end
  end

  push_text("")

  local footer = kit.line()
  footer:add(kit.bar .. " ", "LuoguMuted")
  footer:add(("%d 题"):format(count), "LuoguAlt")
  footer:add((" %s 第 %d/%d 页"):format(kit.bar, state.page, pages), "LuoguAlt")
  footer:add((" %s %d 条"):format(kit.bar, #(data and data.result or {})), "LuoguAlt")
  push(footer)

  local hints = kit.line()
  local function hint(key, desc)
    if hints.text ~= "" then
      hints:add("   ")
    end
    hints:add(key, "LuoguKey")
    hints:add(" " .. desc, "LuoguMuted")
  end
  hint("q", "关闭")
  hint("<CR>", "打开")
  hint("/", "搜索")
  hint("d", "难度")
  hint("n/p", "翻页")
  hint("r", "刷新")
  push(hints)

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

function M.fetch()
  if state.loading then
    return
  end
  state.loading = true
  state.error = nil
  M.render()

  local cfg = config.get()
  api.list({
    page = state.page,
    keyword = state.keyword,
    difficulty = state.difficulty,
    type = cfg.problem_type,
  }, function(data, err)
    state.loading = false
    if not state.buf or not vim.api.nvim_buf_is_valid(state.buf) then
      return
    end
    if err then
      state.data = nil
      state.error = err.msg
      return M.render()
    end
    state.data = data
    state.error = nil
    M.render()
  end)
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

function M.close()
  local buf, win, prev_tab = state.buf, state.win, state.prev_tab

  state.buf = nil
  state.win = nil
  state.prev_tab = nil

  if win and vim.api.nvim_win_is_valid(win) then
    local tab = vim.api.nvim_win_get_tabpage(win)
    local wins = vim.api.nvim_tabpage_list_wins(tab)
    if #wins == 1 and #vim.api.nvim_list_tabpages() == 1 then
      -- Last window of the last tab: closing it would quit Neovim. Swap the
      -- buffer out instead, so the window survives.
      pcall(vim.api.nvim_win_set_buf, win, vim.api.nvim_create_buf(true, false))
    else
      pcall(vim.api.nvim_win_close, win, true)
    end
  end

  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end

  if prev_tab and vim.api.nvim_tabpage_is_valid(prev_tab) then
    pcall(vim.api.nvim_set_current_tabpage, prev_tab)
  end
end

local function current_problem()
  return state.row_to_problem[vim.fn.line(".") - 1]
end

local function page_size()
  return math.max(state.data and state.data.perPage or 50, 1)
end

local function set_keymaps(buf)
  local function map(lhs, fn, desc)
    vim.keymap.set("n", lhs, fn, { buffer = buf, nowait = true, silent = true, desc = desc })
  end

  map("<CR>", function()
    local problem = current_problem()
    if not problem or not problem.pid then
      return vim.notify("这一行没有题目", LOG.WARN)
    end
    require("luogu.ui.problem").open(problem.pid)
  end, "Luogu: open problem")

  map("q", function()
    M.close()
  end, "Luogu: close list")

  map("r", function()
    M.fetch()
  end, "Luogu: refresh")

  map("/", function()
    local keyword = vim.fn.input("搜索: ", state.keyword or "")
    state.keyword = keyword ~= "" and keyword or nil
    state.page = 1
    M.fetch()
  end, "Luogu: search")

  map("d", function()
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
      M.fetch()
    end)
  end, "Luogu: filter difficulty")

  map("n", function()
    local count = state.data and state.data.count or 0
    if state.page * page_size() >= count then
      return vim.notify("已经是最后一页", LOG.INFO)
    end
    state.page = state.page + 1
    M.fetch()
  end, "Luogu: next page")

  map("p", function()
    if state.page <= 1 then
      return vim.notify("已经是第一页", LOG.INFO)
    end
    state.page = state.page - 1
    M.fetch()
  end, "Luogu: previous page")
end

function M.open()
  if state.buf and vim.api.nvim_buf_is_valid(state.buf) then
    local win = state.win
    if win and vim.api.nvim_win_is_valid(win) and vim.api.nvim_win_get_buf(win) == state.buf then
      vim.api.nvim_set_current_win(win)
      return
    end
    for _, w in ipairs(vim.api.nvim_list_wins()) do
      if vim.api.nvim_win_get_buf(w) == state.buf then
        state.win = w
        vim.api.nvim_set_current_win(w)
        return
      end
    end
    state.buf, state.win = nil, nil
  end

  -- Own tab, so `:q` can only close this tab and falls back to the user's one.
  local prev_tab = vim.api.nvim_get_current_tabpage()
  vim.cmd("tabnew")

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].filetype = "luogu-list"
  vim.bo[buf].modifiable = false
  vim.b[buf].luogu_list = true

  vim.api.nvim_win_set_buf(0, buf)
  state.buf = buf
  state.win = vim.api.nvim_get_current_win()
  state.prev_tab = prev_tab
  pcall(vim.api.nvim_set_option_value, "wrap", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "number", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "relativenumber", false, { win = state.win })
  pcall(vim.api.nvim_set_option_value, "cursorline", true, { win = state.win })

  vim.api.nvim_create_autocmd("BufWipeout", {
    buffer = buf,
    once = true,
    callback = function()
      if state.buf == buf then
        state.buf = nil
        state.win = nil
        state.prev_tab = nil
      end
    end,
  })

  set_keymaps(buf)
  ensure_tags()
  M.fetch()
end

---@return table|nil data cached list payload
function M.get_data()
  return state.data
end

M.state = state

return M
