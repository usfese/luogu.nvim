local M = {}

local links = {
  LuoguPid = "Identifier",
  LuoguTitle = "Title",
  LuoguMuted = "Comment",
  LuoguAlt = "Comment",
  LuoguLogo = "Keyword",
  LuoguKey = "Special",
  LuoguHeader = "Title",
  LuoguOk = "DiagnosticOk",
  LuoguWarn = "DiagnosticWarn",
  LuoguError = "DiagnosticError",
  LuoguPending = "DiagnosticInfo",
  LuoguDiff0 = "Comment",
  LuoguDiff1 = "String",
  LuoguDiff2 = "DiagnosticWarn",
  LuoguDiff3 = "Constant",
  LuoguDiff4 = "DiagnosticOk",
  LuoguDiff5 = "Function",
  LuoguDiff6 = "Type",
  LuoguDiff7 = "Special",
  LuoguDiff8 = "Error",
}

function M.setup()
  for name, target in pairs(links) do
    vim.api.nvim_set_hl(0, name, { link = target, default = true })
  end
end

return M
