local M = {}

local kit = require("luogu.ui.kit")
local status = require("luogu.status")
local langs = require("luogu.langs")

local function split_lines(text)
  text = tostring(text or ""):gsub("\r\n", "\n")
  if text:sub(-1) == "\n" then
    text = text:sub(1, -2)
  end
  if text == "" then
    return {}
  end
  local out = {}
  for line in (text .. "\n"):gmatch("([^\n]*)\n") do
    out[#out + 1] = line
  end
  return out
end

local function strip_ansi(text)
  return (tostring(text or ""):gsub("\27%[[%d;]*m", ""))
end

local function fence_for(text)
  local width = 3
  for _, line in ipairs(split_lines(text)) do
    local run = line:match("^(~+)")
    if run and #run >= width then
      width = #run + 1
    end
  end
  return ("~"):rep(width)
end

local function tag_label(tags_by_id, id)
  local tag = tags_by_id and tags_by_id[id]
  if type(tag) == "table" and tag.name then
    return tag.name
  end
  if type(tag) == "string" then
    return tag
  end
  return "#" .. tostring(id)
end

local function fmt_mem(kb)
  if kb == nil then
    return "-"
  end
  return ("%.1f MiB"):format(kb / 1024)
end

local function fmt_score(score)
  if score == nil then
    return "-"
  end
  return tostring(score)
end

local function fmt_time(ms)
  if ms == nil then
    return "-"
  end
  return tostring(ms) .. " ms"
end

---@param problem table
---@param tags_by_id table|nil id -> { name } or name string
---@return { lines: string[], marks: table[] }
function M.problem_document(problem, tags_by_id)
  problem = problem or {}
  local lines, marks = {}, {}

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

  local content = problem.content or {}
  local pid = problem.pid or "?"

  push(kit.line():add("luogu.com.cn/problem/" .. pid, "LuoguMuted"))
  push(kit.line():add(("%s. %s"):format(pid, problem.name or ""), "LuoguTitle"))

  local submitted = problem.total_submit or 0
  local accepted = problem.total_accepted or 0
  local rate = ("%.1f%%"):format(accepted / math.max(submitted, 1) * 100)
  local limits = problem.limits or {}
  local time_text = limits.time_ms and ("%d ms"):format(limits.time_ms) or "—"
  local mem_text = limits.memory_kb and ("%.1f MiB"):format(limits.memory_kb / 1024) or "—"

  local meta = kit.line()
  meta:add(status.difficulty(problem.difficulty), status.difficulty_hl(problem.difficulty))
  meta:add(" " .. kit.bar .. " ", "LuoguMuted")
  meta:add("通过 " .. rate, "LuoguAlt")
  meta:add((" (%d/%d)"):format(accepted, submitted), "LuoguMuted")
  meta:add(" " .. kit.bar .. " ", "LuoguMuted")
  meta:add(time_text, "LuoguAlt")
  meta:add(" " .. kit.bar .. " ", "LuoguMuted")
  meta:add(mem_text, "LuoguAlt")

  local tag_names = {}
  for _, id in ipairs(problem.tags or {}) do
    tag_names[#tag_names + 1] = tag_label(tags_by_id, id)
  end
  if #tag_names > 0 then
    meta:add(" " .. kit.bar .. " ", "LuoguMuted")
    meta:add(table.concat(tag_names, "、"), "LuoguMuted")
  end
  push(meta)

  local function section(title, body)
    if type(body) ~= "string" then
      return
    end
    body = body:gsub("\r\n", "\n"):gsub("%s+$", "")
    if body == "" then
      return
    end
    push_text("")
    push(kit.line():add("## " .. title, "LuoguHeader"))
    push_text("")
    for _, line in ipairs(split_lines(body)) do
      push_text(line)
    end
  end

  section("题目背景", content.background)
  section("题目描述", content.description)
  section("输入格式", content.format_i)
  section("输出格式", content.format_o)

  for i, sample in ipairs(problem.samples or {}) do
    local input = sample[1] or ""
    local output = sample[2] or ""
    push_text("")
    push(kit.line():add(("## 样例 #%d"):format(i), "LuoguHeader"))
    push_text("")
    push(kit.line():add("**输入**", "LuoguAlt"))
    push_text("")
    local fence = fence_for(input)
    push_text(fence .. "text")
    for _, line in ipairs(split_lines(input)) do
      push_text(line)
    end
    push_text(fence)
    if output ~= "" then
      push_text("")
      push(kit.line():add("**输出**", "LuoguAlt"))
      push_text("")
      local out_fence = fence_for(output)
      push_text(out_fence .. "text")
      for _, line in ipairs(split_lines(output)) do
        push_text(line)
      end
      push_text(out_fence)
    end
  end

  section("提示", content.hint)

  return { lines = lines, marks = marks }
end

---@param problem table
---@param tags_by_id table|nil
---@return string[]
function M.problem_markdown(problem, tags_by_id)
  return M.problem_document(problem, tags_by_id).lines
end

---@param record table
---@return { lines: string[], marks: table[] }
function M.record_lines(record)
  record = record or {}
  local lines, marks = {}, {}

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

  local st = status.get(record.status)
  local lang = record.language and langs.by_id[tonumber(record.language)]
  local token = ("%s (%s)"):format(st.name, st.short)

  local icon = st.hl == "LuoguOk" and kit.icons.ac
    or (st.hl == "LuoguMuted" and kit.icons.todo or kit.icons.na)

  local head = kit.line()
  head:add(icon .. " ", st.hl)
  head:add(token, st.hl)
  head:add(" " .. kit.bar .. " ", "LuoguMuted")
  head:add(fmt_score(record.score) .. " 分", "LuoguAlt")
  head:add(" " .. kit.bar .. " ", "LuoguMuted")
  head:add(fmt_time(record.time_ms), "LuoguAlt")
  head:add(" " .. kit.bar .. " ", "LuoguMuted")
  head:add(fmt_mem(record.memory_kb), "LuoguAlt")
  head:add(" " .. kit.bar .. " ", "LuoguMuted")
  head:add(lang and lang.name or "-", "LuoguAlt")
  head:add(" " .. kit.bar .. " ", "LuoguMuted")
  head:add("O2 " .. (record.enable_o2 and "是" or "否"), "LuoguAlt")

  local judge = record.judge
  if type(judge) == "table" and judge.subtasks and #judge.subtasks > 0 then
    local passed = 0
    for _, sub in ipairs(judge.subtasks) do
      if sub.status == 12 then
        passed = passed + 1
      end
    end
    head:add(" " .. kit.bar .. " ", "LuoguMuted")
    head:add(("%d/%d 子任务"):format(passed, #judge.subtasks), "LuoguAlt")
  end
  push(head)

  if status.is_running(record.status) then
    push_text("")
    push(kit.line():add("评测中…", "LuoguPending"))
    return { lines = lines, marks = marks }
  end

  local compile = record.compile
  if type(compile) == "table" and compile.success == false then
    push_text("")
    push(kit.line():add("编译信息", "LuoguHeader"))
    for _, line in ipairs(split_lines(strip_ansi(compile.message))) do
      push(kit.line():add(line, "LuoguError"))
    end
  end

  if type(judge) == "table" and judge.subtasks and #judge.subtasks > 0 then
    push_text("")
    push(kit.line():add("子任务", "LuoguHeader"))
    for _, sub in ipairs(judge.subtasks) do
      local sub_status = status.get(sub.status)
      local row = kit.line()
      row:add("  #" .. tostring(sub.id or "?"), "LuoguPid")
      row:add("  ")
      row:add(sub_status.short, sub_status.hl)
      row:add((" "):rep(math.max(1, 6 - #sub_status.short)))
      row:add(fmt_score(sub.score) .. " 分")
      row:add("  " .. fmt_time(sub.time_ms), "LuoguAlt")
      row:add("  " .. fmt_mem(sub.memory_kb), "LuoguAlt")
      push(row)

      if record.show_status then
        for _, tc in ipairs(sub.test_cases or {}) do
          local tc_status = status.get(tc.status)
          local tc_row = kit.line()
          tc_row:add("    " .. kit.icons.caret .. " #" .. tostring(tc.id or "?"), "LuoguMuted")
          tc_row:add("  ")
          tc_row:add(tc_status.short, tc_status.hl)
          tc_row:add("  " .. fmt_time(tc.time_ms), "LuoguMuted")
          tc_row:add("  " .. fmt_mem(tc.memory_kb), "LuoguMuted")
          push(tc_row)
        end
      end
    end
  end

  return { lines = lines, marks = marks }
end

M.strip_ansi = strip_ansi
M.split_lines = split_lines
M.fence_for = fence_for

return M
