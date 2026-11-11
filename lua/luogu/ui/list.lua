local M = {}

local api = require("luogu.api")
local config = require("luogu.config")
local status = require("luogu.status")

local LOG = vim.log.levels

local NAME_W = 40
local DIFF_W = 14
local TAG_W = 20

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

local function dwidth(s)
  return vim.fn.strdisplaywidth(s)
end

--- Truncate to `width` display cells, appending an ellipsis when cut.
local function fit(s, width)
  s = s or ""
  if width <= 0 then
    return ""
  end
  if dwidth(s) <= width then
    return s
  end
  local ellipsis = "…"
  local budget = width - dwidth(ellipsis)
  local out = {}
  local used = 0
  for i = 0, vim.fn.strchars(s) - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w = dwidth(ch)
    if used + w > budget then
      break
    end
    out[#out + 1] = ch
    used = used + w
  end
  return table.concat(out) .. ellipsis
end

local function tag_name(id)
  if state.tags and state.tags.by_id and state.tags.by_id[id] then
    return state.tags.by_id[id].name
  end
  return "#" .. tostring(id)
end

local function rate_text(p)
  local submit = tonumber(p.total_submit) or 0
  local accepted = tonumber(p.total_accepted) or 0
  return ("%5.1f%%"):format(accepted / math.max(submit, 1) * 100)
end

--- Build one list row plus its highlight marks (byte columns).
local function build_row(problem)
  local parts = {}
  local marks = {}
  local col = 0

  local function push(s)
    parts[#parts + 1] = s
    col = col + #s
  end

  local function mark(s, hl)
    local start_col = col
    push(s)
    marks[#marks + 1] = { start_col = start_col, end_col = col, hl = hl }
  end

  local pid = tostring(problem.pid or "?")
  mark(pid, "LuoguPid")
  push((" "):rep(math.max(1, 7 - #pid)))

  local name = fit(problem.name or "", NAME_W)
  push(name)
  push((" "):rep(NAME_W - dwidth(name)))
  push(" ")

  local diff = fit(status.difficulty(problem.difficulty), DIFF_W)
  mark(diff, status.difficulty_hl(problem.difficulty))
  push((" "):rep(DIFF_W - dwidth(diff)))
  push(" ")

  push(rate_text(problem))
  push("  ")

  local names = {}
  for _, id in ipairs(problem.tags or {}) do
    if #names >= 2 then
      break
    end
    names[#names + 1] = tag_name(id)
  end
  local tags = fit(table.concat(names, ","), TAG_W)
  if tags ~= "" then
    mark("[" .. tags .. "]", "LuoguMuted")
  end

  return table.concat(parts), marks
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

  if data then
    lines[#lines + 1] = ("Luogu 题库 · %d 题 · 第 %d 页"):format(count, state.page)
  else
    lines[#lines + 1] = "Luogu 题库"
  end

  local diff_label = state.difficulty ~= nil and status.difficulty(state.difficulty) or "全部难度"
  local keyword = state.keyword and state.keyword ~= "" and state.keyword or "无"
  lines[#lines + 1] = ("筛选: %s   搜索: %s   (q 关闭, / 搜索, d 难度, n/p 翻页, r 刷新)"):format(diff_label, keyword)
  lines[#lines + 1] = ("-"):rep(80)

  state.row_to_problem = {}

  if state.error then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "加载失败：" .. state.error
  elseif not data then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "加载中…"
  elseif #data.result == 0 then
    lines[#lines + 1] = ""
    lines[#lines + 1] = "没有找到题目"
  else
    for _, problem in ipairs(data.result) do
      local row = #lines
      local line, row_marks = build_row(problem)
      lines[#lines + 1] = line
      state.row_to_problem[row] = problem
      for _, m in ipairs(row_marks) do
        marks[#marks + 1] = { row = row, start_col = m.start_col, end_col = m.end_col, hl = m.hl }
      end
    end
  end

  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, state.ns, 0, -1)
  for _, m in ipairs(marks) do
    pcall(vim.api.nvim_buf_set_extmark, buf, state.ns, m.row, m.start_col, {
      end_col = m.end_col,
      hl_group = m.hl,
    })
  end
  vim.bo[buf].modifiable = false

  local win = state.win
  if win and vim.api.nvim_win_is_valid(win) and #lines >= 4 and not state.error then
    pcall(vim.api.nvim_win_set_cursor, win, { 4, 0 })
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
