local M = {}

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
---@return string[]
function M.problem_markdown(problem, tags_by_id)
  problem = problem or {}
  local lines = {}
  local function add(line)
    lines[#lines + 1] = line
  end

  local function section(title, body)
    if type(body) ~= "string" then
      return
    end
    body = body:gsub("\r\n", "\n"):gsub("%s+$", "")
    if body == "" then
      return
    end
    add("")
    add("## " .. title)
    add("")
    for _, line in ipairs(split_lines(body)) do
      add(line)
    end
  end

  add(("# %s %s"):format(problem.pid or "?", problem.name or ""))

  local content = problem.content or {}
  local names = {}
  for _, id in ipairs(problem.tags or {}) do
    names[#names + 1] = tag_label(tags_by_id, id)
  end
  local tag_text = #names > 0 and table.concat(names, "、") or "无"

  local submitted = problem.total_submit or 0
  local accepted = problem.total_accepted or 0
  local rate = ("%.1f%%"):format(accepted / math.max(submitted, 1) * 100)

  local limits = problem.limits or {}
  local time_text = limits.time_ms and ("%d ms"):format(limits.time_ms) or "—"
  local mem_text = limits.memory_kb and ("%.1f MiB"):format(limits.memory_kb / 1024) or "—"

  add("")
  add("- **难度**：" .. status.difficulty(problem.difficulty))
  add("- **标签**：" .. tag_text)
  add(("- **通过**：%d/%d（%s）"):format(accepted, submitted, rate))
  add(("- **限制**：%s / %s"):format(time_text, mem_text))

  section("题目背景", content.background)
  section("题目描述", content.description)
  section("输入格式", content.format_i)
  section("输出格式", content.format_o)

  for i, sample in ipairs(problem.samples or {}) do
    local input = sample[1] or ""
    local output = sample[2] or ""
    add("")
    add(("## 样例 #%d"):format(i))
    add("")
    add("**输入**")
    add("")
    local fence = fence_for(input)
    add(fence .. "text")
    for _, line in ipairs(split_lines(input)) do
      add(line)
    end
    add(fence)
    if output ~= "" then
      add("")
      add("**输出**")
      add("")
      local out_fence = fence_for(output)
      add(out_fence .. "text")
      for _, line in ipairs(split_lines(output)) do
        add(line)
      end
      add(out_fence)
    end
  end

  section("提示", content.hint)

  return lines
end

---@param record table
---@return { lines: string[], marks: table[] }
function M.record_lines(record)
  record = record or {}
  local lines, marks = {}, {}

  local st = status.get(record.status)
  local rid = tostring(record.rid or "?")
  local prefix = ("记录 #%s   "):format(rid)
  lines[#lines + 1] = prefix .. st.name .. " (" .. st.short .. ")"
  marks[#marks + 1] = { row = 0, start_col = #prefix, end_col = #lines[1], hl = st.hl }

  local lang = record.language and langs.by_id[tonumber(record.language)]
  local parts = {
    "得分 " .. fmt_score(record.score),
    "时间 " .. fmt_time(record.time_ms),
    "内存 " .. fmt_mem(record.memory_kb),
    "语言 " .. (lang and lang.name or "-"),
    "O2 " .. (record.enable_o2 and "是" or "否"),
  }
  lines[#lines + 1] = table.concat(parts, " | ")
  lines[#lines + 1] = "-"

  if status.is_running(record.status) then
    lines[#lines + 1] = "评测中…"
    return { lines = lines, marks = marks }
  end

  local compile = record.compile
  if type(compile) == "table" and compile.success == false then
    lines[#lines + 1] = "编译信息:"
    local message = strip_ansi(compile.message)
    for _, line in ipairs(split_lines(message)) do
      lines[#lines + 1] = line
    end
  end

  local judge = record.judge
  if type(judge) == "table" and judge.subtasks and #judge.subtasks > 0 then
    lines[#lines + 1] = "子任务:"
    for _, sub in ipairs(judge.subtasks) do
      local sub_status = status.get(sub.status)
      lines[#lines + 1] = ("  #%s  %s  %s  %s  %s"):format(
        tostring(sub.id or "?"),
        sub_status.short,
        fmt_score(sub.score),
        fmt_time(sub.time_ms),
        fmt_mem(sub.memory_kb)
      )
      if record.show_status then
        for _, tc in ipairs(sub.test_cases or {}) do
          local tc_status = status.get(tc.status)
          lines[#lines + 1] = ("    - #%s %s %s %s"):format(
            tostring(tc.id or "?"),
            tc_status.short,
            fmt_time(tc.time_ms),
            fmt_mem(tc.memory_kb)
          )
        end
      end
    end
  end

  return { lines = lines, marks = marks }
end

M.split_lines = split_lines
M.fence_for = fence_for

return M
