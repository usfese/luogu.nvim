local M = {}

-- Only languages Luogu reports with disabled=false in /_lfe/config.
-- Fields: key, id, name, filetype, extension, can_o2, order.
local rows = {
  { "pascal", 1, "Pascal", "pascal", "pas", true, 2 },
  { "c", 2, "C", "c", "c", true, 3 },
  { "cpp14gcc9", 28, "C++14 (GCC 9)", "cpp", "cpp", true, 4 },
  { "cpp98", 3, "C++98", "cpp", "cpp", true, 5 },
  { "cpp11", 4, "C++11", "cpp", "cpp", true, 6 },
  { "cpp14", 11, "C++14", "cpp", "cpp", true, 7 },
  { "cpp17", 12, "C++17", "cpp", "cpp", true, 8 },
  { "cpp20", 27, "C++20", "cpp", "cpp", true, 9 },
  { "cpp23", 34, "C++23", "cpp", "cpp", true, 10 },
  { "python3", 7, "Python 3", "python", "py", false, 13 },
  { "pypy3", 25, "PyPy 3", "python", "py", false, 14 },
  { "java8", 8, "Java 8", "java", "java", false, 15 },
  { "java21", 33, "Java 21", "java", "java", false, 16 },
  { "rust", 15, "Rust", "rust", "rs", true, 17 },
  { "go", 14, "Go", "go", "go", false, 18 },
  { "haskell", 19, "Haskell", "haskell", "hs", true, 19 },
  { "ocaml", 30, "OCaml", "ocaml", "ml", true, 20 },
  { "julia", 31, "Julia", "julia", "jl", false, 21 },
  { "lua", 32, "Lua", "lua", "lua", false, 22 },
  { "kotlin", 21, "Kotlin/JVM", "kotlin", "kt", false, 24 },
  { "scala", 22, "Scala", "scala", "scala", false, 25 },
  { "csharp", 17, "C# Mono", "cs", "cs", false, 26 },
  { "node", 9, "Node.js LTS", "javascript", "js", false, 29 },
  { "php", 16, "PHP", "php", "php", false, 31 },
  { "ruby", 13, "Ruby", "ruby", "rb", false, 32 },
  { "perl", 23, "Perl", "perl", "pl", false, 33 },
}

local list = {}
local by_key, by_id = {}, {}

for _, r in ipairs(rows) do
  local lang = {
    key = r[1],
    id = r[2],
    name = r[3],
    ft = r[4],
    ext = r[5],
    can_o2 = r[6],
    order = r[7],
  }
  list[#list + 1] = lang
  by_key[lang.key] = lang
  by_id[lang.id] = lang
end

table.sort(list, function(a, b)
  return a.order < b.order
end)

---@param accept any[]|nil
---@return table[]
function M.for_problem(accept)
  if not accept or next(accept) == nil then
    return vim.deepcopy(list)
  end
  local allowed = {}
  for _, id in ipairs(accept) do
    allowed[tonumber(id) or id] = true
  end
  local out = {}
  for _, lang in ipairs(list) do
    if allowed[lang.id] then
      out[#out + 1] = lang
    end
  end
  return out
end

---@param problem table|nil
---@return table|nil lang, string|nil err
function M.pick(problem)
  local candidates = M.for_problem(problem and problem.accept_languages)
  local allowed = {}
  for _, lang in ipairs(candidates) do
    allowed[lang.id] = true
  end

  local last = tonumber(problem and problem.last_language)
  if last and allowed[last] then
    return M.by_id[last]
  end

  local configured = require("luogu.config").get().language
  local cfg_lang = M.by_key[configured]
  if cfg_lang and allowed[cfg_lang.id] then
    return cfg_lang
  end

  if #candidates > 0 then
    return candidates[1]
  end
  return nil, "题目不接受任何已支持的语言"
end

M.list = list
M.by_key = by_key
M.by_id = by_id

return M
