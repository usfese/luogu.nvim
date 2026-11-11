local M = {}

local api = require("luogu.api")
local config = require("luogu.config")

local VERSION = 1
local CONCURRENCY = 1
local DELAY = 250
local RETRIES = 2

local running = false

local function cache_path()
  return vim.fs.joinpath(config.data_dir(), "problem_index.json")
end

local function split_pid(pid)
  local kind, num = tostring(pid or ""):match("^(%a+)(%d+)$")
  if kind then
    return kind, tonumber(num) or 0
  end
  return tostring(pid or ""), 0
end

local function less(a, b)
  local ka, na = split_pid(a.pid)
  local kb, nb = split_pid(b.pid)
  if ka == kb then
    return na < nb
  end
  return ka < kb
end

---@return table|nil
function M.load()
  local path = cache_path()
  if vim.fn.filereadable(path) == 0 then
    return nil
  end
  local ok, lines = pcall(vim.fn.readfile, path)
  if not ok or type(lines) ~= "table" then
    return nil
  end
  local decoded, data = pcall(vim.json.decode, table.concat(lines, "\n"))
  if not decoded or type(data) ~= "table" or data.version ~= VERSION then
    return nil
  end
  if type(data.problems) ~= "table" or #data.problems == 0 then
    return nil
  end
  return data
end

---@param data table
---@return boolean
function M.save(data)
  local path = cache_path()
  local tmp = path .. ".tmp"
  local ok, encoded = pcall(vim.json.encode, data)
  if not ok then
    return false
  end
  ok = pcall(vim.fn.writefile, { encoded }, tmp)
  if not ok then
    return false
  end
  return pcall(vim.uv.fs_rename, tmp, path)
end

---@param data table|nil
---@return boolean
function M.stale(data)
  if not data then
    return true
  end
  if data.partial then
    return true
  end
  local ttl = tonumber(config.get().cache_ttl) or 0
  if ttl <= 0 then
    return true
  end
  return (os.time() - (tonumber(data.updated_at) or 0)) >= ttl
end

function M.is_syncing()
  return running
end

local function is_block(err)
  local msg = tostring(err and err.msg or "")
  return msg:find("反爬", 1, true) ~= nil or (err ~= nil and err.status == 429)
end

local function merge(base, pages, total)
  local seen = {}
  local problems = {}
  local function add(item)
    if type(item) == "table" and item.pid and not seen[item.pid] then
      seen[item.pid] = true
      problems[#problems + 1] = item
    end
  end
  for _, item in ipairs(base or {}) do
    add(item)
  end
  for page = 1, total do
    for _, item in ipairs(pages[page] or {}) do
      add(item)
    end
  end
  table.sort(problems, less)
  return problems
end

--- Fetch the index, resuming a partial cache. Saves progress on interruption.
---@param opts { type?: string, on_progress?: fun(done: integer, total: integer) }|nil
---@param cb fun(data: table|nil, err: table|nil)
function M.sync(opts, cb)
  opts = opts or {}
  if running then
    return cb(nil, { msg = "题库正在同步" })
  end
  running = true

  local problem_type = opts.type or config.get().problem_type
  local existing = M.load()
  local resume = existing ~= nil and existing.partial == true and existing.type == problem_type

  local start_page = resume and ((tonumber(existing.fetched_pages) or 0) + 1) or 1
  local base_problems = resume and existing.problems or {}
  local pages = {}
  local pages_done = resume and (tonumber(existing.fetched_pages) or 0) or 0
  local total = 0
  local remaining = 0
  local cursor = start_page + 1
  local server_per_page = 50
  local finished = false
  local attempts = {}

  local function progress()
    if opts.on_progress then
      opts.on_progress(pages_done, total)
    end
  end

  local function snapshot(partial)
    local problems = merge(base_problems, pages, total)
    return {
      version = VERSION,
      updated_at = os.time(),
      type = problem_type,
      per_page = server_per_page,
      count = #problems,
      problems = problems,
      partial = partial,
      fetched_pages = math.min(pages_done, total),
      total_pages = total,
    }
  end

  local function fail(err)
    if finished then
      return
    end
    finished = true
    running = false

    local data = nil
    if pages_done > 0 and (resume or not existing) then
      data = snapshot(true)
      M.save(data)
    end
    cb(data, err)
  end

  local function finish()
    if finished then
      return
    end
    finished = true
    running = false

    local data = snapshot(false)
    if not M.save(data) then
      return cb(nil, { msg = "题库缓存写入失败：" .. cache_path() })
    end
    cb(data, nil)
  end

  local worker
  local fetch_page

  fetch_page = function(page)
    api.list({ page = page, type = problem_type }, function(data, err)
      if finished then
        return
      end
      if not data then
        if is_block(err) then
          return fail(err)
        end
        attempts[page] = (attempts[page] or 0) + 1
        if attempts[page] <= RETRIES then
          return vim.defer_fn(function()
            fetch_page(page)
          end, 1200 * attempts[page])
        end
        return fail(err)
      end

      pages[page] = data.result
      pages_done = pages_done + 1
      remaining = remaining - 1
      progress()

      -- Keep progress across restarts: this run can take minutes.
      if pages_done % 30 == 0 and pages_done < total then
        M.save(snapshot(true))
      end

      if remaining <= 0 then
        finish()
      else
        vim.defer_fn(worker, DELAY)
      end
    end)
  end

  worker = function()
    if finished then
      return
    end
    local page = cursor
    if page > total then
      return
    end
    cursor = cursor + 1
    fetch_page(page)
  end

  api.list({ page = start_page, type = problem_type }, function(data, err)
    if finished then
      return
    end
    if not data then
      return fail(err)
    end

    pages[start_page] = data.result
    pages_done = pages_done + 1
    server_per_page = data.perPage or 50
    total = math.max(1, math.ceil((data.count or #data.result) / math.max(server_per_page, 1)))
    if pages_done > total then
      pages_done = total
    end
    progress()

    if start_page >= total then
      return finish()
    end

    remaining = total - start_page
    for _ = 1, math.min(CONCURRENCY, remaining) do
      worker()
    end
  end)
end

M.path = cache_path
M.version = VERSION

return M
