local M = {}

local statuses = {
  [-1] = { name = "Unshown", short = "N/A", hl = "LuoguMuted" },
  [0] = { name = "Waiting", short = "Waiting", hl = "LuoguPending" },
  [1] = { name = "Judging", short = "Judging", hl = "LuoguPending" },
  [2] = { name = "Compile Error", short = "CE", hl = "LuoguWarn" },
  [3] = { name = "Output Limit Exceeded", short = "OLE", hl = "LuoguWarn" },
  [4] = { name = "Memory Limit Exceeded", short = "MLE", hl = "LuoguWarn" },
  [5] = { name = "Time Limit Exceeded", short = "TLE", hl = "LuoguWarn" },
  [6] = { name = "Wrong Answer", short = "WA", hl = "LuoguError" },
  [7] = { name = "Runtime Error", short = "RE", hl = "LuoguError" },
  [11] = { name = "Unknown Error", short = "UKE", hl = "LuoguError" },
  [12] = { name = "Accepted", short = "AC", hl = "LuoguOk" },
  [14] = { name = "Unaccepted", short = "NAC", hl = "LuoguError" },
  [21] = { name = "Hack Success", short = "Hack Success", hl = "LuoguOk" },
  [22] = { name = "Hack Failure", short = "Hack Failure", hl = "LuoguError" },
  [23] = { name = "Hack Skipped", short = "Hack Skipped", hl = "LuoguMuted" },
}

local difficulties = {
  [0] = "暂无评定",
  [1] = "入门",
  [2] = "普及−",
  [3] = "普及",
  [4] = "普及+/提高−",
  [5] = "提高",
  [6] = "提高+/省选−",
  [7] = "省选/NOI−",
  [8] = "NOI/NOI+/CTS",
}

---@param id integer|nil
---@return { name: string, short: string, hl: string }
function M.get(id)
  local s = statuses[tonumber(id) or -1]
  if s then
    return s
  end
  return { name = ("Unknown (%s)"):format(tostring(id)), short = "?", hl = "LuoguMuted" }
end

---@param id integer|nil
---@return boolean
function M.is_running(id)
  id = tonumber(id)
  return id == 0 or id == 1
end

---@param id integer|nil
---@return string
function M.difficulty(id)
  return difficulties[tonumber(id) or 0] or ("未知(%s)"):format(tostring(id))
end

---@return string
function M.difficulty_hl(id)
  local d = tonumber(id) or 0
  if d < 0 or d > 8 then
    d = 0
  end
  return "LuoguDiff" .. d
end

return M
