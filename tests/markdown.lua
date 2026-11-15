local markdown = require("luogu.markdown")
local problem = {
    pid = "P1", name = "测试",
    content = { description = [=[ $a \le b$ 和 $x^{2}$、$\bm a$；`$x^2$ <br>`
```cpp
$x^2$ <br>
```
未知 $\unknown{x}$<br>换行]=] },
    samples = { { "a```b\n", "x <y>\n" } },
    limits = { time = { 1000, 1000 }, memory = { 524288, 524288 } },
}
local text = table.concat(markdown.document(problem), "\n")
assert(text:find("a ≤ b", 1, true))
assert(text:find("x²", 1, true))
assert(not text:find("\\bm", 1, true))
assert(text:find("`$x^2$ <br>`", 1, true))
assert(text:find("```cpp\n$x^2$ <br>\n```", 1, true))
assert(text:find("$\\unknown{x}$", 1, true))
assert(text:find("````\na```b", 1, true))
assert(text:find("1000 ms", 1, true))
assert(not text:find("1000, 1000", 1, true))
print("markdown conversion checks passed")
