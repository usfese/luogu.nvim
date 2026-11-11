-- Unit tests for luogu.nvim. Run with:
--   nvim --headless --clean --cmd "set rtp+=$PWD" -l tests/run.lua

local script = debug.getinfo(1, "S").source:gsub("^@", "")
local root = vim.fn.fnamemodify(script, ":p:h:h")
vim.opt.runtimepath:append(root)

local fixtures = vim.fs.joinpath(root, "tests", "fixtures")

require("luogu").setup({ data_dir = vim.fn.tempname() })

local api = require("luogu.api")
local auth = require("luogu.auth")
local config = require("luogu.config")
local http = require("luogu.http")
local langs = require("luogu.langs")
local render = require("luogu.render")
local status = require("luogu.status")

local passed, failed = 0, 0

local function ok(name, cond, detail)
  if cond then
    passed = passed + 1
  else
    failed = failed + 1
    print(("FAIL: %s%s"):format(name, detail and (" — " .. tostring(detail)) or ""))
  end
end

local function eq(name, actual, expected)
  ok(name, vim.deep_equal(actual, expected), ("expected %s, got %s"):format(vim.inspect(expected), vim.inspect(actual)))
end

local function contains(name, haystack, needle)
  ok(name, type(haystack) == "string" and haystack:find(needle, 1, true) ~= nil, ("missing %q"):format(needle))
end

local function load_json(name)
  local path = vim.fs.joinpath(fixtures, name)
  local lines = vim.fn.readfile(path)
  return vim.json.decode(table.concat(lines, "\n"))
end

-- http ----------------------------------------------------------------
eq("urlencode plus", http.urlencode("A+B"), "A%2BB")
eq("urlencode space", http.urlencode("a b"), "a%20b")
eq("urlencode utf8", http.urlencode("中文"), "%E4%B8%AD%E6%96%87")
eq("urlencode separators", http.urlencode("a/b&c=d"), "a%2Fb%26c%3Dd")
eq("urlencode unreserved", http.urlencode("-._~"), "-._~")
eq(
  "encode_query sorted and escaped",
  http.encode_query({ page = 1, type = "P", keyword = "A+B" }),
  "keyword=A%2BB&page=1&type=P"
)
eq("encode_query empty", http.encode_query({}), nil)

-- api ----------------------------------------------------------------
local problem = api.normalize_problem(load_json("problem_p1001.json"))
eq("problem pid", problem.pid, "P1001")
eq("problem name", problem.name, "A+B Problem")
eq("problem difficulty", problem.difficulty, 1)
eq("problem sample", problem.samples[1][1], "20 30\n")
eq("problem sample out", problem.samples[1][2], "50\n")
eq("problem time limit", problem.limits.time_ms, 1000)
eq("problem memory limit", problem.limits.memory_kb, 524288)
ok("problem accepts cpp17", vim.tbl_contains(problem.accept_languages, 12))
eq("problem provider", problem.provider, "洛谷")
eq("problem last_code", problem.last_code, "")

local list = api.normalize_summary(load_json("problem_list.json").data.problems.result[1])
eq("summary pid", list.pid, "P1000")
eq("summary name", list.name, "超级玛丽游戏")
eq("summary difficulty", list.difficulty, 1)
eq("summary submits", list.total_submit, 1930803)
eq("summary tags", #list.tags, 2)

local ac = api.normalize_record(load_json("record_ac.json"))
eq("record currentData status", ac.status, 12)
eq("record rid", ac.rid, 123)
eq("record score", ac.score, 100)
eq("record time", ac.time_ms, 23)
eq("record memory", ac.memory_kb, 1024)
eq("record language", ac.language, 12)
eq("record o2", ac.enable_o2, false)
eq("record compile success", ac.compile.success, true)
eq("record compile message", ac.compile.message, nil)
eq("record show_status", ac.show_status, true)
eq("record subtask count", #ac.judge.subtasks, 1)
eq("record subtask status", ac.judge.subtasks[1].status, 12)
eq("record subtask testcases", #ac.judge.subtasks[1].test_cases, 0)

local ce = api.normalize_record(load_json("record_ce.json"))
eq("record data envelope status", ce.status, 2)
eq("record data envelope rid", ce.rid, 124)
eq("record ce compile failed", ce.compile.success, false)
ok("record ce raw message keeps ansi", ce.compile.message:find("\27", 1, true) ~= nil)
eq("record ce judge", ce.judge, nil)

local nulls = vim.json.decode(
  '{"data":{"problem":{"pid":"P9","difficulty":null,"tags":null,"content":{"hint":null},'
    .. '"samples":null,"limits":null,"acceptLanguages":null,"totalSubmit":null,"totalAccepted":null}}}'
)
local null_problem = api.normalize_problem(nulls)
eq("null difficulty", null_problem.difficulty, 0)
eq("null tags", null_problem.tags, {})
eq("null hint", null_problem.content.hint, nil)
eq("null samples", null_problem.samples, {})
eq("null limits", null_problem.limits.time_ms, nil)
eq("null accepts", null_problem.accept_languages, {})
eq("null total submit", null_problem.total_submit, 0)

local list_payload = api.normalize_list(load_json("problem_list.json"))
eq("normalize_list perPage", list_payload.perPage, 50)
eq("normalize_list count", list_payload.count, 16728)
eq("normalize_list size", #list_payload.result, 3)
eq("normalize_list first pid", list_payload.result[1].pid, "P1000")
local no_list, no_list_err = api.normalize_list({ data = { problems = vim.NIL } })
eq("normalize_list missing payload", no_list, nil)
ok("normalize_list error", no_list_err ~= nil)

local tags_payload = api.normalize_tags(load_json("tags.json"))
eq("normalize_tags size", #tags_payload.tags, 6)
eq("normalize_tags by_id name", tags_payload.by_id[1].name, "模拟")
eq("normalize_tags parent", tags_payload.by_id[1].parent, 110)
eq("normalize_tags null parent", tags_payload.by_id[2].parent, nil)
eq("normalize_tags types", #tags_payload.types, 4)
local no_tags, no_tags_err = api.normalize_tags({ tags = vim.NIL })
eq("normalize_tags missing payload", no_tags, nil)
ok("normalize_tags error", no_tags_err ~= nil)

-- langs --------------------------------------------------------------
local seen, unique = {}, true
for _, lang in ipairs(langs.list) do
  if seen[lang.id] then
    unique = false
  end
  seen[lang.id] = true
end
ok("lang ids unique", unique)
eq("cpp17 id", langs.by_key.cpp17.id, 12)
local filtered = langs.for_problem({ 12, 7 })
eq("for_problem size", #filtered, 2)
eq("for_problem order", { filtered[1].key, filtered[2].key }, { "cpp17", "python3" })
eq("for_problem empty returns all", #langs.for_problem({}), #langs.list)
eq("pick honors last_language", langs.pick({ accept_languages = { 12, 7 }, last_language = 7 }).key, "python3")
eq("pick falls back to config", langs.pick({ accept_languages = { 12, 7 }, last_language = 5 }).key, "cpp17")
local none, nerr = langs.pick({ accept_languages = { 99 } })
eq("pick no candidate", none, nil)
ok("pick no candidate error", nerr ~= nil)

-- status -------------------------------------------------------------
eq("status AC short", status.get(12).short, "AC")
eq("status AC name", status.get(12).name, "Accepted")
ok("status running 0", status.is_running(0))
ok("status running 1", status.is_running(1))
ok("status not running 12", not status.is_running(12))
eq("status unknown short", status.get(999).short, "?")
eq("status unknown name", status.get(999).name, "Unknown (999)")
eq("difficulty name", status.difficulty(2), "普及−")
eq("difficulty highlight", status.difficulty_hl(8), "LuoguDiff8")

-- render -------------------------------------------------------------
local tags_by_id = { [1] = { name = "模拟" }, [2] = { name = "字符串" } }
local md = table.concat(render.problem_markdown(problem, tags_by_id), "\n")
contains("markdown title", md, "P1001. A+B Problem")
contains("markdown difficulty", md, "入门")
contains("markdown tags", md, "模拟")
contains("markdown pass rate", md, "通过 ")
contains("markdown time limit", md, "1000 ms")
contains("markdown memory limit", md, "512.0 MiB")
contains("markdown background", md, "## 题目背景")
contains("markdown description", md, "## 题目描述")
contains("markdown input", md, "## 输入格式")
contains("markdown output", md, "## 输出格式")
contains("markdown sample heading", md, "## 样例 #1")
contains("markdown fence", md, "~~~text")
contains("markdown sample input", md, "20 30")
contains("markdown sample output", md, "50")
contains("markdown hint", md, "## 提示")
contains("markdown unknown tag placeholder", table.concat(render.problem_markdown(problem, nil), "\n"), "#1")

local kit = require("luogu.ui.kit")
eq("kit pad cjk", kit.pad("中文", 6), "中文  ")
eq("kit right", kit.right("7", 3), "  7")
eq("kit fit truncates", kit.fit("abcdef", 4), "abc…")
eq("kit fit keeps", kit.fit("ab", 4), "ab")
eq("kit logo lines", #kit.logo, 5)

local doc = render.problem_document(problem, tags_by_id)
eq("doc url line", doc.lines[1], "luogu.com.cn/problem/P1001")
eq("doc title line", doc.lines[2], "P1001. A+B Problem")
local diff_mark
for _, mark in ipairs(doc.marks) do
  if mark.row == 2 and mark.hl == "LuoguDiff1" then
    diff_mark = mark
  end
end
ok("doc difficulty mark", diff_mark ~= nil)
contains("doc meta bar", doc.lines[3], "│ 通过 57.9%")

local bare = api.normalize_problem(
  vim.json.decode('{"data":{"problem":{"pid":"P1","name":"T","content":{"description":"body"}}}}')
)
local bare_md = table.concat(render.problem_markdown(bare, {}), "\n")
ok("markdown omits empty hint", bare_md:find("## 提示", 1, true) == nil)
ok("markdown omits empty tag segment", bare_md:find("标签", 1, true) == nil)

local two_tags = api.normalize_problem(
  vim.json.decode('{"data":{"problem":{"pid":"P2","name":"X","tags":[1,2],"content":{}}}}')
)
contains(
  "markdown tags joined",
  table.concat(render.problem_markdown(two_tags, tags_by_id), "\n"),
  "模拟、字符串"
)

local ac_lines = render.record_lines(ac)
local ac_text = table.concat(ac_lines.lines, "\n")
contains("record line accepted", ac_text, "Accepted")
contains("record header icon", ac_text, "✓ Accepted")
contains("record line short", ac_text, "(AC)")
contains("record line score", ac_text, "100 分")
contains("record line language", ac_text, "C++17")
contains("record line subtask", ac_text, "子任务")
local token_mark
for _, mark in ipairs(ac_lines.marks) do
  local text = ac_lines.lines[mark.row + 1]:sub(mark.start_col + 1, mark.end_col)
  if text == "Accepted (AC)" then
    token_mark = mark
  end
end
ok("record mark for status token", token_mark ~= nil and token_mark.hl == "LuoguOk")
eq("record mark row", token_mark and token_mark.row, 0)

local ce_text = table.concat(render.record_lines(ce).lines, "\n")
ok("record ce strips ansi", ce_text:find("\27", 1, true) == nil)
contains("record ce message", ce_text, "expected ';'")
contains("record ce header", ce_text, "编译信息")

local running_text = table.concat(render.record_lines({ rid = 1, status = 1, score = 0 }).lines, "\n")
contains("record running", running_text, "评测中…")
ok("record running hides subtasks", running_text:find("子任务", 1, true) == nil)

local fence = render.fence_for("~~~\ninside\n")
ok("fence grows", #fence >= 4)

-- auth ---------------------------------------------------------------
eq("parse_uid", auth.parse_uid("a=1; _uid=123; b=2"), "123")
eq("parse_uid missing", auth.parse_uid("a=1"), nil)
eq("cookie path", auth.cookie_path(), vim.fs.joinpath(config.data_dir(), "cookie"))

-- csrf ---------------------------------------------------------------
eq(
  "csrf name first",
  api.parse_csrf('<meta name="csrf-token" content="1794447326:BAVx+AB/c=">'),
  "1794447326:BAVx+AB/c="
)
eq("csrf content first", api.parse_csrf('<meta content="a+b/c=" name="csrf-token">'), "a+b/c=")
eq("csrf single quotes", api.parse_csrf("<meta name='csrf-token' content='tok+1/2='>"), "tok+1/2=")
eq("csrf missing", api.parse_csrf("<html></html>"), nil)

-- command ------------------------------------------------------------
local command = require("luogu.command")
ok("complete suggests subcommands", vim.tbl_contains(command.complete("op", ":Luogu op"), "open"))
ok(
  "complete open returns list",
  type(command.complete("", ":Luogu open ")) == "table"
)

-- auth file handling ------------------------------------------------
vim.fn.writefile({ "Cookie: a=1; _uid=42; b=2" }, auth.cookie_path())
eq("get_cookie strips prefix", auth.get_cookie(), "a=1; _uid=42; b=2")
eq("parse_uid from file", auth.parse_uid(auth.get_cookie()), "42")

config.setup({ data_dir = config.data_dir(), cookie = "Cookie: __client_id=z; _uid=7" })
eq("config cookie wins", auth.get_cookie(), "__client_id=z; _uid=7")
config.setup({ data_dir = config.data_dir(), cookie = "" })

local api_mod = require("luogu.api")
local real_validate, real_user = api_mod.validate_cookie, api_mod.user
local real_inputsecret = vim.fn.inputsecret
api_mod.validate_cookie = function(_, cb)
  cb({ uid = "55", name = "Tester" }, nil)
end
api_mod.user = function(_, cb)
  cb({ name = "Tester" }, nil)
end
vim.fn.inputsecret = function()
  return "Cookie: __client_id=q; _uid=55; extra=1"
end
vim.fn.delete(auth.cookie_path())
auth.login()
vim.fn.inputsecret = real_inputsecret
api_mod.validate_cookie, api_mod.user = real_validate, real_user
eq("login stores cookie", auth.get_cookie(), "__client_id=q; _uid=55; extra=1")
eq("login chmods 600", ("%03o"):format(vim.uv.fs_stat(auth.cookie_path()).mode % 512), "600")

auth.logout()
eq("logout deletes cookie", vim.fn.filereadable(auth.cookie_path()), 0)

print(("%d checks"):format(passed + failed))
print(("%d failures"):format(failed))
if failed > 0 then
  os.exit(1)
end
