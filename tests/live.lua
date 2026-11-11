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
local tabs_before = #vim.api.nvim_list_tabpages()
local base_buf = vim.api.nvim_get_current_buf()

-- seed the index instead of pulling all 335 pages in a test
local cache = require("luogu.cache")
if not cache.save({
  version = cache.version,
  updated_at = os.time(),
  type = "P",
  per_page = 20,
  count = #list.result,
  problems = list.result,
}) then
  fail("could not seed the problem cache")
end

local function problem_rows()
  local n = 0
  for _, row in pairs(ui_list.state.row_map) do
    if row.kind == "problem" then
      n = n + 1
    end
  end
  return n
end

local function feed(keys)
  vim.api.nvim_feedkeys(vim.api.nvim_replace_termcodes(keys, true, false, true), "x", false)
end

ui_list.open("menu")
if ui_list.state.view ~= "menu" then
  fail("menu page is not active")
end
local menu_text = table.concat(vim.api.nvim_buf_get_lines(ui_list.state.buf, 0, -1, false), "\n")
if not menu_text:find("Problems", 1, true) or not menu_text:find("Close", 1, true) then
  fail("menu buttons missing")
end
if vim.api.nvim_win_get_config(ui_list.state.win).relative ~= "editor" then
  fail("menu is not a floating window")
end
print("menu ok")

ui_list.open("problems")
wait_for(function()
  local buf = ui_list.state.buf
  if not (buf and vim.api.nvim_buf_is_valid(buf)) then
    return false
  end
  for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
    if line:sub(1, 5) == "P1000" then
      return true
    end
  end
  return false
end, "list buffer with P1000")

local list_buf = ui_list.state.buf
local list_win = ui_list.state.win
if not (list_win and vim.api.nvim_win_is_valid(list_win)) then
  fail("list window missing")
end
if vim.api.nvim_win_get_config(list_win).relative ~= "editor" then
  fail("list is not a floating window")
end
local list_lines = vim.api.nvim_buf_get_lines(list_buf, 0, -1, false)
if not table.concat(list_lines, "\n"):find("Problems", 1, true) then
  fail("list breadcrumb missing")
end
if problem_rows() ~= 20 then
  fail(("page 1 should show 20 rows, got %d"):format(problem_rows()))
end
if not table.concat(list_lines, "\n"):find("第 1/3 页", 1, true) then
  fail("page counter missing")
end

feed("l")
if ui_list.state.page ~= 2 or problem_rows() ~= 20 then
  fail("l did not go to page 2")
end
feed("h")
if ui_list.state.page ~= 1 then
  fail("h did not go back to page 1")
end
ui_list.goto_page(3)
if problem_rows() ~= 10 then
  fail(("last page should show 10 rows, got %d"):format(problem_rows()))
end
ui_list.goto_page(1)

ui_list.state.keyword = "P1001"
ui_list.render()
if problem_rows() ~= 1 then
  fail(("keyword filter should keep 1 row, got %d"):format(problem_rows()))
end
ui_list.state.keyword = nil
ui_list.render()
print("paging ok")

local all_before = ui_list.state.all
ui_list.open_problem("P1001")

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
if not desc_text:find("P1001. A+B Problem", 1, true) then
  fail("description header missing title")
end
if desc_text:find("## 题目描述", 1, true) == nil then
  fail("description buffer missing markdown section")
end
if desc_text:find("入门", 1, true) == nil or desc_text:find("模拟", 1, true) == nil then
  fail("description header missing difficulty or tag name")
end

local code_path = vim.api.nvim_buf_get_name(code_buf)
if not code_path:match("problems/P1001%.cpp$") then
  fail("unexpected code path: " .. code_path)
end
print("UI ok")

local code_win = vim.fn.bufwinid(code_buf)
local desc_win = vim.fn.bufwinid(desc_buf)
if code_win < 0 or desc_win < 0 then
  fail("problem windows missing")
end

vim.api.nvim_win_close(desc_win, true)
if not vim.api.nvim_win_is_valid(code_win) then
  fail("closing the statement closed the code window too")
end

-- closing the code window returns to the list popup, not the home tab
vim.api.nvim_win_close(code_win, true)
wait_for(function()
  return ui_list.state.win ~= nil and vim.api.nvim_win_is_valid(ui_list.state.win)
end, "list restored after closing the problem")
if ui_list.state.all ~= all_before then
  fail("list was refetched instead of reused")
end
if #vim.api.nvim_list_tabpages() ~= tabs_before + 1 then
  fail("problem view did not stay in the plugin tab")
end
print("stack ok")

ui_list.close()
if #vim.api.nvim_list_tabpages() ~= tabs_before then
  fail("plugin tab did not close")
end
if vim.api.nvim_get_current_buf() ~= base_buf then
  fail("did not fall back to the previous buffer")
end
print("tabs ok")

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
