-- Load the fork's upstream modules separately from an installed leetcode.nvim.
local root = debug.getinfo(1, "S").source:sub(2):match("^(.*)/lua/luogu/upstream%.lua$")
local modules = {}
local env = setmetatable({}, { __index = _G })
local original_require = require

local function isolated_require(name)
    if not (name == "leetcode" or name:match("^leetcode[.%-]")) then
        return original_require(name)
    end
    if modules[name] ~= nil then return modules[name] end
    local path = root .. "/lua/" .. name:gsub("%.", "/")
    local file = io.open(path .. ".lua", "r")
    if file then
        file:close()
        path = path .. ".lua"
    else
        path = path .. "/init.lua"
    end
    local chunk, err = loadfile(path)
    if not chunk then error(err, 2) end
    setfenv(chunk, env)
    local value = chunk(name)
    if value == nil then value = true end
    modules[name] = value
    return value
end

env.require = isolated_require
return { require = isolated_require, env = env }
