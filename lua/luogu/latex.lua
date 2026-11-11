local M = {}

-- Commands that map to a single character.
local symbols = {
  le = "≤",
  leq = "≤",
  ge = "≥",
  geq = "≥",
  ne = "≠",
  neq = "≠",
  times = "×",
  cdot = "·",
  cdots = "…",
  ldots = "…",
  dots = "…",
  to = "→",
  rightarrow = "→",
  leftarrow = "←",
  Rightarrow = "⇒",
  Leftarrow = "⇐",
  leftrightarrow = "↔",
  infty = "∞",
  pm = "±",
  mp = "∓",
  bmod = "mod",
  mod = "mod",
  div = "÷",
  sum = "∑",
  prod = "∏",
  int = "∫",
  ["in"] = "∈",
  notin = "∉",
  subset = "⊂",
  subseteq = "⊆",
  supset = "⊃",
  supseteq = "⊇",
  cup = "∪",
  cap = "∩",
  emptyset = "∅",
  sim = "∼",
  approx = "≈",
  equiv = "≡",
  circ = "∘",
  degree = "°",
  angle = "∠",
  triangle = "△",
  because = "∵",
  therefore = "∴",
  oplus = "⊕",
  otimes = "⊗",
  land = "∧",
  lor = "∨",
  lfloor = "⌊",
  rfloor = "⌋",
  lceil = "⌈",
  rceil = "⌉",
  langle = "⟨",
  rangle = "⟩",
  quad = " ",
  qquad = "  ",
  left = "",
  right = "",
  big = "",
  Big = "",
  bigg = "",
  Bigg = "",
  displaystyle = "",
  limits = "",
}

-- Commands that take one braced argument and should print just the argument.
local wrappers = {
  "text",
  "textrm",
  "textbf",
  "textit",
  "mathrm",
  "mathtt",
  "mathbf",
  "mathit",
  "mathcal",
  "mathbb",
  "operatorname",
  "bm",
  "boldsymbol",
  "overline",
  "underline",
  "hat",
  "bar",
  "vec",
  "dot",
}

local entities = {
  amp = "&",
  lt = "<",
  gt = ">",
  quot = '"',
  apos = "'",
  nbsp = " ",
  hellip = "…",
  mdash = "—",
  ndash = "–",
  times = "×",
  divide = "÷",
  le = "≤",
  ge = "≥",
  middot = "·",
}

local function decode_entities(text)
  text = text:gsub("&#(%d+);", function(dec)
    local code = tonumber(dec)
    if not code then
      return ""
    end
    local ok, char = pcall(vim.fn.nr2char, code)
    return ok and char or ""
  end)
  text = text:gsub("&#x(%x+);", function(hex)
    local code = tonumber(hex, 16)
    if not code then
      return ""
    end
    local ok, char = pcall(vim.fn.nr2char, code)
    return ok and char or ""
  end)
  return (text:gsub("&(%a+);", function(name)
    return entities[name] or ("&" .. name .. ";")
  end))
end

local function clean_math(src)
  local text = src

  -- Spacing and escapes first, so later passes see plain characters.
  text = text:gsub("\\[%s,;!:]", " ")
  -- Protect literal braces before grouping braces get stripped.
  text = text:gsub("\\{", "\1")
  text = text:gsub("\\}", "\2")
  text = text:gsub("\\%$", "$")
  text = text:gsub("\\%%", "%%")
  text = text:gsub("\\_", "_")
  text = text:gsub("\\&", "&")
  text = text:gsub("\\#", "#")
  text = text:gsub("\\\\", "; ")

  -- \frac{a}{b} -> a/b
  text = text:gsub("\\[dt]?frac%s*{([^{}]*)}%s*{([^{}]*)}", "%1/%2")
  text = text:gsub("\\[dt]?frac(%d)(%d)", "%1/%2")
  -- \sqrt{x} -> √(x)
  text = text:gsub("\\sqrt%s*{([^{}]*)}", "√(%1)")
  text = text:gsub("\\sqrt%s*%[([^%]]*)%]%s*{([^{}]*)}", "√[%1](%2)")

  for _, name in ipairs(wrappers) do
    text = text:gsub("\\" .. name .. "%s*{([^{}]*)}", "%1")
    text = text:gsub("\\" .. name .. "%s+([%a%d])", "%1")
  end

  -- Remaining known commands, then unknown ones lose their backslash.
  text = text:gsub("\\([a-zA-Z]+)", function(name)
    return symbols[name] or name
  end)

  -- Grouping braces inside math only; literal braces arrive as \{ later.
  for _ = 1, 3 do
    text = text:gsub("{([^{}]*)}", "%1")
  end
  text = text:gsub("\1", "{")
  text = text:gsub("\2", "}")
  text = text:gsub("%s+", " ")
  return vim.trim(text)
end

--- Turn Luogu's Markdown+LaTeX into something readable in a plain buffer.
---@param text string|nil
---@return string|nil
function M.clean(text)
  if type(text) ~= "string" or text == "" then
    return text
  end

  local out = decode_entities(text:gsub("\r\n", "\n"))

  -- Display math first, then inline math.
  out = out:gsub("%$%$(.-)%$%$", function(inner)
    return clean_math(inner)
  end)
  out = out:gsub("%$(.-)%$", function(inner)
    return clean_math(inner)
  end)

  -- Escapes that appear outside math.
  out = out:gsub("\\%%", "%%")
  out = out:gsub("\\_", "_")
  out = out:gsub("\\&", "&")
  out = out:gsub("\\#", "#")
  out = out:gsub("\\%$", "$")
  out = out:gsub("\\ ", " ")

  return out
end

M.symbols = symbols
M.clean_math = clean_math

return M
