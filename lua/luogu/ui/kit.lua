local M = {}

M.bar = "│"

M.icons = {
  ac = "✓",
  na = "✗",
  todo = "·",
  caret = "›",
}

M.logo = {
  [[ _      _   _    ___     ____   _   _  ]],
  [[| |    | | | |  / _ \   / ___| | | | | ]],
  [[| |    | | | | | | | | | |  _  | | | | ]],
  [[| |___ | |_| | | |_| | | |_| | | |_| | ]],
  [[|_____  \___/   \___/   \____|  \___/  ]],
}

local devicons_checked = false
local devicons = nil

---@param ext string|nil
---@return string|nil
function M.devicon(ext)
  if not devicons_checked then
    devicons_checked = true
    local ok, mod = pcall(require, "nvim-web-devicons")
    devicons = ok and mod or nil
  end
  if not (devicons and ext) then
    return nil
  end
  local ok, icon = pcall(devicons.get_icon, nil, ext, { default = false })
  return ok and icon or nil
end

---@param s string
---@return integer
function M.width(s)
  return vim.fn.strdisplaywidth(s)
end

---@param s string
---@param width integer
---@return string
function M.pad(s, width)
  local fill = width - M.width(s)
  if fill <= 0 then
    return s
  end
  return s .. (" "):rep(fill)
end

---@param s string
---@param width integer
---@return string
function M.right(s, width)
  local fill = width - M.width(s)
  if fill <= 0 then
    return s
  end
  return (" "):rep(fill) .. s
end

--- Truncate to `width` display cells, appending an ellipsis when cut.
---@param s string
---@param width integer
---@return string
function M.fit(s, width)
  s = s or ""
  if width <= 0 then
    return ""
  end
  if M.width(s) <= width then
    return s
  end
  local ellipsis = "…"
  local budget = width - M.width(ellipsis)
  local out = {}
  local used = 0
  for i = 0, vim.fn.strchars(s) - 1 do
    local ch = vim.fn.strcharpart(s, i, 1)
    local w = M.width(ch)
    if used + w > budget then
      break
    end
    out[#out + 1] = ch
    used = used + w
  end
  return table.concat(out) .. ellipsis
end

local Line = {}
Line.__index = Line

--- A single screen line: text plus byte-column highlight spans.
---@return table
function M.line()
  return setmetatable({ text = "", marks = {} }, Line)
end

---@param text string
---@param hl string|nil
---@return table
function Line:add(text, hl)
  if text == nil or text == "" then
    return self
  end
  local start = #self.text
  self.text = self.text .. text
  if hl then
    self.marks[#self.marks + 1] = { start_col = start, end_col = #self.text, hl = hl }
  end
  return self
end

---@param width integer
---@return table
function Line:pad_to(width)
  return self:add((" "):rep(math.max(0, width - M.width(self.text))))
end

---@return integer
function Line:width()
  return M.width(self.text)
end

return M
