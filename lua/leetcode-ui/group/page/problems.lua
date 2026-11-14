local list = require("luogu.list")

local Title = require("leetcode-ui.lines.title")
local Button = require("leetcode-ui.lines.button.menu")
local BackButton = require("leetcode-ui.lines.button.menu.back")
local Buttons = require("leetcode-ui.group.buttons.menu")
local Page = require("leetcode-ui.group.page")

local footer = require("leetcode-ui.lines.footer")
local header = require("leetcode-ui.lines.menu-header")

local page = Page()

page:insert(header)

page:insert(Title({ "Menu" }, "Problems"))

local problems = Button("List", {
    icon = "",
    sc = "p",
    on_press = list.open,
})

local back = BackButton("menu")

page:insert(Buttons({
    problems,
    back,
}))

page:insert(footer)

return page
