local M = {}

local defaults = {
  data_dir = vim.fn.stdpath("data") .. "/luogu.nvim",
  cookie = "", -- full Cookie header; when non-empty takes precedence over data_dir/cookie
  language = "cpp17", -- key from langs.lua
  o2 = false,
  problem_type = "P",
  cache_ttl = 604800, -- 题库索引多久更新一次，单位秒；0 表示每次打开都更新
  http = { timeout = 30000, user_agent = "luogu.nvim/0.1" },
  keys = {
    submit = "<localleader>s",
    language = "<localleader>l",
    list = "<localleader>t",
    open_url = "<localleader>o",
  },
}

local current = nil

local function normalize_dir(path)
  local abs = vim.fn.fnamemodify(vim.fn.expand(path), ":p")
  if #abs > 1 then
    abs = abs:gsub("/+$", "")
  end
  return abs
end

local function ensure_dirs(cfg)
  vim.fn.mkdir(cfg.data_dir, "p")
  vim.fn.mkdir(vim.fs.joinpath(cfg.data_dir, "problems"), "p")
end

---@param opts table|nil
---@return table
function M.setup(opts)
  assert(vim.fn.has("nvim-0.10") == 1, "luogu.nvim requires Neovim >= 0.10")
  assert(vim.fn.executable("curl") == 1, "luogu.nvim requires curl")

  local merged = vim.tbl_deep_extend("force", vim.deepcopy(defaults), opts or {})
  assert(type(merged.data_dir) == "string" and merged.data_dir ~= "", "luogu.nvim: data_dir must be a string")
  assert(type(merged.cookie) == "string", "luogu.nvim: cookie must be a string")
  assert(not merged.cookie:find("[\r\n]"), "luogu.nvim: cookie must not contain newlines")
  assert(type(merged.language) == "string", "luogu.nvim: language must be a string")

  merged.data_dir = normalize_dir(merged.data_dir)
  current = merged
  ensure_dirs(current)
  return current
end

---@return table
function M.get()
  if not current then
    current = vim.deepcopy(defaults)
    current.data_dir = normalize_dir(current.data_dir)
    ensure_dirs(current)
  end
  return current
end

---@return string absolute path without trailing separator
function M.data_dir()
  return M.get().data_dir
end

M.defaults = defaults

return M
