# luogu.nvim

在 Neovim 里做洛谷的题。

## 要求

需要 Neovim 0.10 以上和 `curl`

## 安装

```lua
{
  "usfese/luogu.nvim",
  cmd = "Luogu",
  config = function()
    require("luogu").setup({})
  end,
}
```

`cmd` 表示第一次执行 `:Luogu` 时才加载插件。想让它常驻就写成 `{ "usfese/luogu.nvim", config = ... }`。不设置 `setup` 也能用，默认值见下。

## 默认配置

```lua
require("luogu").setup({
  data_dir = vim.fn.stdpath("data") .. "/luogu.nvim", -- cookie 和代码文件放这里
  cookie = "",          -- 完整的 Cookie 头，非空时优先于 data_dir/cookie
  language = "cpp17",   -- 见下面「语言」
  o2 = false,           -- 只对支持 O2 的语言生效
  problem_type = "P",   -- P 是主题库
  http = { timeout = 30000, user_agent = "luogu.nvim/0.1" },
  keys = {
    submit = "<localleader>s",
    language = "<localleader>l",
    list = "<localleader>t",
    open_url = "<localleader>o",
  },
})
```

## 语言

`language` 和 `:Luogu lang` 都填表里的 key，默认 `cpp17`。最后一列表示洛谷给不给开 O2。

| key | 洛谷里的名字 | O2 |
| --- | --- | --- |
| `pascal` | Pascal | ✓ |
| `c` | C | ✓ |
| `cpp14gcc9` | C++14 (GCC 9) | ✓ |
| `cpp98` | C++98 | ✓ |
| `cpp11` | C++11 | ✓ |
| `cpp14` | C++14 | ✓ |
| `cpp17` | C++17 | ✓ |
| `cpp20` | C++20 | ✓ |
| `cpp23` | C++23 | ✓ |
| `python3` | Python 3 | × |
| `pypy3` | PyPy 3 | × |
| `java8` | Java 8 | × |
| `java21` | Java 21 | × |
| `rust` | Rust | ✓ |
| `go` | Go | × |
| `haskell` | Haskell | ✓ |
| `ocaml` | OCaml | ✓ |
| `julia` | Julia | × |
| `lua` | Lua | × |
| `kotlin` | Kotlin/JVM | × |
| `scala` | Scala | × |
| `csharp` | C# Mono | × |
| `node` | Node.js LTS | × |
| `php` | PHP | × |
| `ruby` | Ruby | × |
| `perl` | Perl | × |

## 登录

在浏览器登录洛谷，控制台执行 `document.cookie`，复制整串，回到 Neovim 执行 `:Luogu login` 粘贴。需要有 `__client_id` 和 `_uid`。

插件会先拿它请求一次 `/record/list`，再写进 `<data_dir>/cookie`（权限 0600）。`:Luogu logout` 只删这个文件，配置里写的 `cookie` 依然有效。

## 命令

| 命令 | 作用 |
| --- | --- |
| `:Luogu` 或 `:Luogu list` | 题库列表 |
| `:Luogu open P1001` | 打开题目，左边题面右边代码 |
| `:Luogu submit [pid]` | 提交当前代码，或指定题目的文件 |
| `:Luogu lang [key]` | 换语言 |
| `:Luogu login` / `logout` | 存或删 Cookie |
| `:Luogu record 12345` | 看某次评测 |
| `:Luogu P1001` | `open P1001` 的简写 |

## 键位

| 键 | 场景 | 作用 |
| --- | --- | --- |
| `<localleader>s` | 代码、题面 | 提交 |
| `<localleader>l` | 代码 | 选语言 |
| `<localleader>t` | 代码 | 打开题库 |
| `<localleader>o` | 代码 | 浏览器打开题目页 |
| `<CR>` | 题库 | 打开光标下的题 |
| `/` `d` `n` `p` `r` | 题库 | 搜索、难度、翻页、刷新 |
| `q` | 题库、题面、评测 | 关掉 |
| `o` `r` | 评测 | 浏览器打开记录、重新拉取 |

## 几个行为

- 每次提交前重新抓题目页的 CSRF token。403 或 419 重试一次，401 不重试。
- 评测浮窗每秒查一次，最多 180 次，关掉浮窗后不再发请求。
- 语言写死在 `lua/luogu/langs.lua`，只收洛谷当前启用的那些。

## 注意

非官方插件，洛谷没有公开 API，站点改版随时会坏。Cookie 明文存在 `data_dir`，只发给 `www.luogu.com.cn`，没有别的主机、没有统计、加载插件时不发请求。

布局和交互参考了 [kawre/leetcode.nvim](https://github.com/kawre/leetcode.nvim)（MIT），没有复制它的代码。

## 开发

```bash
nvim --headless --clean --cmd "set rtp+=$PWD" -l tests/run.lua   # 单元测试，不联网
nvim --headless --clean --cmd "set rtp+=$PWD" -l tests/live.lua  # 联网加界面冒烟测试
```

`tests/fixtures/` 里的题面正文是占位符，只保留测试要用的字段，重新抓的时候别把题面原文带回来。

## License

MIT
