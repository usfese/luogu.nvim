-- Run with XDG_CACHE_HOME pointing at an empty temporary directory.
local calls = {}
package.loaded["luogu.client"] = {
    list = function(opts, cb)
        calls[#calls + 1] = opts
        if opts.keyword then
            return cb({ count = 1, problems = { { pid = "P9999", name = "Remote" } } })
        end
        if opts.page == 1 then
            cb({ count = 3, problems = { { pid = "P1000", name = "A" }, { pid = "P1001", name = "B" } } })
        elseif opts.page == 2 then
            cb({ count = 3, problems = { { pid = "P1002", name = "C" } } })
        else
            error("unexpected index page")
        end
    end,
}
local index = require("luogu.index")
local problems, status, searched
local unsubscribe = index.open(function(items, info) problems, status = items, info end)
index.search("P9999", function(data) searched = data.problems[1].pid end)
assert(vim.wait(5000, function() return status and status.complete and searched end, 20), "index timed out")
assert(#problems == 3 and problems[3].pid == "P1002")
assert(searched == "P9999")
assert(vim.fn.filereadable(vim.fn.stdpath("cache") .. "/luogu/problem-index-v1.json") == 1)
unsubscribe()
print("index and search checks passed")
