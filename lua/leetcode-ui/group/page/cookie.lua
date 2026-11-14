local list = require("luogu.list")

local Title = require("leetcode-ui.lines.title")
local Buttons = require("leetcode-ui.group.buttons.menu")
local Page = require("leetcode-ui.group.page")
local Button = require("leetcode-ui.lines.button.menu")
local BackButton = require("leetcode-ui.lines.button.menu.back")

local header = require("leetcode-ui.lines.menu-header")
local footer = require("leetcode-ui.lines.footer")

local page = Page()

page:insert(header)

page:insert(Title({ "Menu" }, "Cookie"))

local update = Button("Update", {
    icon = "󱛬",
    sc = "u",
    on_press = list.cookie_prompt,
})

local delete = Button("Delete / Sign out", {
    icon = "󱛪",
    sc = "d",
    on_press = function()
        require("luogu.client").logout()
        vim.notify("已退出洛谷登录", vim.log.levels.INFO, { title = "洛谷" })
    end,
})

local back = BackButton("menu")

page:insert(Buttons({
    update,
    delete,
    back,
}))

page:insert(footer)

return page
