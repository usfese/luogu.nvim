-- Run with XDG_DATA_HOME set to an isolated temporary directory.
local captured
package.loaded["plenary.curl"] = {
    get = function(url, opts)
        captured = { url = url, headers = opts.headers }
        opts.callback({ status = 200, body = vim.json.encode({ user = { uid = 42, name = "Tester" }, data = {} }) })
    end,
}
local client = require("luogu.client")
local result, failure
client.login("Cookie: __client_id=test; _uid=42", function(user, err)
    result, failure = user, err
end)
assert(vim.wait(1000, function() return result or failure end), "login callback timed out")
assert(not failure, failure)
assert(result.uid == 42)
assert(captured.url == "https://www.luogu.com.cn/record/list")
assert(captured.headers["X-Lentille-Request"] == "content-only")
assert(captured.headers.Cookie == "__client_id=test; _uid=42")
assert(vim.fn.readfile(vim.fn.stdpath("data") .. "/luogu/cookie")[1] == "__client_id=test; _uid=42")
print("login regression passed")
