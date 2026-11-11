-- Network + UI smoke test (no credentials required). Run with:
--   nvim --headless --clean --cmd "set rtp+=$PWD" -l tests/live.lua

local script = debug.getinfo(1, "S").source:gsub("^@", "")
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.runtimepath:append(root)

require("luogu").setup({ data_dir = vim.fn.tempname() })

local api = require("luogu.api")
local ui_list = require("luogu.ui.list")
local ui_problem = require("luogu.ui.problem")

local function fail(message)
  print("FAIL: " .. message)
  os.exit(1)
end

local function wait_for(cond, label, timeout)
  if not vim.wait(timeout or 40000, cond, 100) then
    fail("timeout waiting for " .. label)
  end
end

-- 1. problem list ------------------------------------------------------
local list, list_err
api.list({ page = 1, type = "P" }, function(data, err)
  list, list_err = data, err
end)
wait_for(function()
  return list ~= nil or list_err ~= nil
end, "problem list")

if not list then
  fail("list: " .. (list_err and list_err.msg or "no data"))
end
if list.count <= 0 then
  fail("list count is empty")
end
if list.result[1].pid ~= "P1000" then
  fail("expected first pid P1000, got " .. tostring(list.result[1].pid))
end
print("list ok")

-- 2. single problem ----------------------------------------------------
local problem, problem_err
api.problem("P1001", function(data, err)
  problem, problem_err = data, err
end)
wait_for(function()
  return problem ~= nil or problem_err ~= nil
end, "problem P1001")

if not problem then
  fail("problem: " .. (problem_err and problem_err.msg or "no data"))
end
if problem.name ~= "A+B Problem" then
  fail("unexpected problem name: " .. tostring(problem.name))
end
if problem.samples[1] and problem.samples[1][1] ~= "20 30\n" then
  fail("unexpected sample input: " .. vim.inspect(problem.samples[1]))
end
print("P1001 ok")

-- 3. tags --------------------------------------------------------------
local tags, tags_err
api.tags(function(data, err)
  tags, tags_err = data, err
end)
wait_for(function()
  return tags ~= nil or tags_err ~= nil
end, "tags")

if not tags then
  fail("tags: " .. (tags_err and tags_err.msg or "no data"))
end
if #tags.tags < 400 then
  fail(("expected >= 400 tags, got %d"):format(#tags.tags))
end
if not tags.by_id[1] or tags.by_id[1].name ~= "模拟" then
  fail("tags by_id missing id 1")
end
print("tags ok")

-- 4. list UI + problem UI ---------------------------------------------
ui_list.open()
wait_for(function()
  local buf = ui_list.state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:find("P1000", 1, true) then
      return true
    end
  end
  return false
end, "list buffer with P1000")

local list_buf = ui_list.state.buf
local list_lines = vim.api.nvim_buf_get_lines(list_buf, 0, -1, false)
if not list_lines[1]:find("题库", 1, true) then
  fail("list header missing: " .. tostring(list_lines[1]))
end
if not list_lines[4] or list_lines[4]:sub(1, 5) ~= "P1000" then
  fail("first row is not P1000: " .. tostring(list_lines[4]))
end

ui_problem.open("P1001")

local code_buf, desc_buf
wait_for(function()
  code_buf, desc_buf = nil, nil
  for _, buf in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_loaded(buf) then
      if vim.b[buf].luogu_pid == "P1001" and vim.bo[buf].filetype == "cpp" then
        code_buf = buf
      end
      if vim.b[buf].luogu_desc then
        desc_buf = buf
      end
    end
  end
  return code_buf ~= nil and desc_buf ~= nil
end, "problem buffers")

local desc_text = table.concat(vim.api.nvim_buf_get_lines(desc_buf, 0, -1, false), "\n")
if not desc_text:find("A+B Problem", 1, true) then
  fail("description buffer missing problem name")
end
if not desc_text:find("## 题目描述", 1, true) then
  fail("description buffer missing markdown section")
end
if desc_text:find("- **标签**：模拟", 1, true) == nil then
  fail("description buffer did not resolve tag names")
end

local code_path = vim.api.nvim_buf_get_name(code_buf)
if not code_path:match("problems/P1001%.cpp$") then
  fail("unexpected code path: " .. code_path)
end
print("UI ok")

-- 5. invalid cookie ---------------------------------------------------
local cookie_res, cookie_err
api.validate_cookie("__client_id=x; _uid=1", function(data, err)
  cookie_res, cookie_err = data, err
end)
wait_for(function()
  return cookie_res ~= nil or cookie_err ~= nil
end, "cookie validation")

if cookie_res then
  fail("invalid cookie was accepted")
end
local cookie_msg = cookie_err and cookie_err.msg or ""
if not cookie_msg:lower():find("cookie", 1, true) then
  fail("cookie error message lacks 'Cookie': " .. cookie_msg)
end
print("invalid cookie ok")

print("live tests ok")
