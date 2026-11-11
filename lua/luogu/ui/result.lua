local M = {}

local api = require("luogu.api")
local render = require("luogu.render")
local status = require("luogu.status")

local LOG = vim.log.levels
local MAX_ATTEMPTS = 180
local INTERVAL = 1000
local HEIGHT = 18

local ns = vim.api.nvim_create_namespace("luogu.result")

local state = {
  buf = nil,
  win = nil,
  rid = nil,
  attempts = 0,
}

local seq = 0

local function alive()
  return state.buf ~= nil and vim.api.nvim_buf_is_valid(state.buf)
end

local function set_content(lines, marks)
  if not alive() then
    return
  end
  local buf = state.buf
  vim.bo[buf].modifiable = true
  vim.api.nvim_buf_set_lines(buf, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(buf, ns, 0, -1)
  for _, mark in ipairs(marks or {}) do
    pcall(vim.api.nvim_buf_set_extmark, buf, ns, mark.row, mark.start_col, {
      end_col = mark.end_col,
      hl_group = mark.hl,
    })
  end
  vim.bo[buf].modifiable = false
end

function M.close()
  seq = seq + 1
  local win, buf = state.win, state.buf
  state.win, state.buf, state.rid, state.attempts = nil, nil, nil, 0
  if win and vim.api.nvim_win_is_valid(win) then
    pcall(vim.api.nvim_win_close, win, true)
  end
  if buf and vim.api.nvim_buf_is_valid(buf) then
    pcall(vim.api.nvim_buf_delete, buf, { force = true })
  end
end

local function summary(record)
  local st = status.get(record.status)
  return ("%s | %s 分 | %s ms | %s MiB"):format(
    st.short,
    record.score ~= nil and tostring(record.score) or "-",
    record.time_ms ~= nil and tostring(record.time_ms) or "-",
    record.memory_kb ~= nil and ("%.1f"):format(record.memory_kb / 1024) or "-"
  )
end

function M.open(rid)
  rid = tostring(rid or "")
  if not rid:match("^%d+$") then
    return vim.notify("非法记录 ID", LOG.ERROR)
  end

  M.close()
  seq = seq + 1
  local mine = seq

  local buf = vim.api.nvim_create_buf(false, true)
  vim.bo[buf].buftype = "nofile"
  vim.bo[buf].bufhidden = "wipe"
  vim.bo[buf].swapfile = false
  vim.bo[buf].modifiable = false
  vim.bo[buf].filetype = "luogu-result"

  local width = math.min(100, math.floor(vim.o.columns * 0.8))
  local win = vim.api.nvim_open_win(buf, true, {
    relative = "editor",
    width = width,
    height = HEIGHT,
    row = math.max(0, vim.o.lines - HEIGHT - 4),
    col = math.max(0, math.floor((vim.o.columns - width) / 2)),
    style = "minimal",
    border = "rounded",
    title = " Luogu 评测 ",
    zindex = 50,
  })
  pcall(vim.api.nvim_set_option_value, "wrap", true, { win = win })

  state.buf, state.win, state.rid, state.attempts = buf, win, rid, 0

  vim.keymap.set("n", "q", function()
    M.close()
  end, { buffer = buf, nowait = true, silent = true, desc = "Luogu: close result" })

  vim.keymap.set("n", "o", function()
    vim.ui.open("https://www.luogu.com.cn/record/" .. rid)
  end, { buffer = buf, nowait = true, silent = true, desc = "Luogu: open record in browser" })

  vim.api.nvim_create_autocmd("WinClosed", {
    pattern = tostring(win),
    once = true,
    callback = function()
      if state.win == win then
        seq = seq + 1
        state.win, state.buf, state.rid = nil, nil, nil
      end
    end,
  })

  set_content({ ("记录 #%s"):format(rid), "提交成功，等待评测…" })

  local function poll()
    if mine ~= seq or not alive() then
      return
    end
    api.record(rid, function(record, err)
      if mine ~= seq or not alive() then
        return
      end
      if not record then
        set_content({ ("记录 #%s"):format(rid), "", "加载失败：" .. (err and err.msg or "未知错误") })
        return
      end
      local content = render.record_lines(record)
      set_content(content.lines, content.marks)
      if status.is_running(record.status) then
        if state.attempts < MAX_ATTEMPTS then
          state.attempts = state.attempts + 1
          vim.defer_fn(poll, INTERVAL)
        end
        return
      end
      vim.notify(summary(record), LOG.INFO)
    end)
  end

  vim.keymap.set("n", "r", function()
    state.attempts = 0
    poll()
  end, { buffer = buf, nowait = true, silent = true, desc = "Luogu: refresh result" })

  poll()
end

return M
