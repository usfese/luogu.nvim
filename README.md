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
  data_dir = vim.fn.stdpath("data") .. "/luogu.nvim", -- cookie、题库索引、代码文件放这里
  cookie = "",          -- 完整的 Cookie 头，非空时优先于 data_dir/cookie
  language = "cpp17",   -- 见下面「语言」
  o2 = false,           -- 只对支持 O2 的语言生效
  problem_type = "P",   -- P 是主题库
  cache_ttl = 604800,   -- 题库索引多久更新一次（秒），0 表示每次都更新
  http = {
    timeout = 30000,
    user_agent = "Mozilla/5.0 ... Chrome/130.0 Safari/537.36 luogu.nvim/0.1",
  },
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
| `:Luogu` | 菜单 |
| `:Luogu list` | 题库列表 |
| `:Luogu open P1001` | 打开题目，左边题面右边代码 |
| `:Luogu submit [pid]` | 提交当前代码，或指定题目的文件 |
| `:Luogu lang [key]` | 换语言 |
| `:Luogu login` / `logout` | 存或删 Cookie |
| `:Luogu record 12345` | 看某次评测 |
| `:Luogu sync` | 强制重新拉取整个题库索引 |
| `:Luogu P1001` | `open P1001` 的简写 |

## 键位

| 键 | 场景 | 作用 |
| --- | --- | --- |
| `<localleader>s` | 代码、题面 | 提交 |
| `<localleader>l` | 代码 | 选语言 |
| `<localleader>t` | 代码 | 打开题库 |
| `<localleader>o` | 代码 | 浏览器打开题目页 |
| `<CR>` | 菜单、题库 | 选中当前行 |
| `p` | 菜单 | 进题库 |
| `l` | 菜单 | 登录 / 退出登录 |
| `q` | 菜单 | 关闭 |
| `q` | 题库 | 回菜单 |
| `h` `l` | 题库 | 上一页 / 下一页 |
| `g` | 题库 | 输入页码跳转 |
| `n` `p` | 题库 | 下一页 / 上一页 |
| `/` `d` `r` | 题库 | 搜索、难度、刷新 |
| `q` | 题面、评测 | 关掉 |
| `o` `r` | 评测 | 浏览器打开记录、重新拉取 |

## 几个行为

- 题库索引缓存在 `<data_dir>/problem_index.json`。打开题库时如果缓存超过 `cache_ttl`，后台全量拉取（约 335 页，串行限速），进度显示在信息条；分页、搜索、难度筛选都在本地做，翻页不联网。首次同步实测约 8 分钟（335 页），每 30 页写一次盘；中途退出或被杀掉，下次 `:Luogu sync` 或 `r` 从断点继续。
- 题干里的 LaTeX 会转成可读的 Unicode：`$…$` 去掉，`\le` 变 ≤，`\times` 变 ×，`\frac{1}{2}` 变 1/2，样例和代码块不动。
- 洛谷的 WAF 会给非浏览器 UA 返回校验页，所以默认 UA 是浏览器标识加 `luogu.nvim/0.1`，并在 GET 时跟随站点发的校验重定向。同步频率是串行的，被拦时按提示稍后再试，进度会保留。
- 每次提交前重新抓题目页的 CSRF token。403 或 419 重试一次，401 不重试。
- 评测浮窗每秒查一次，最多 180 次，关掉浮窗后不再发请求。
- 菜单和题库是同一个浮窗的两个页面，题库在自己的 tab 里。`q` 逐级返回：题目里关掉代码窗口会回到题库（数据不重新拉），题库 `q` 回菜单，菜单 `q` 关掉整个视图，不会顺手退出 Neovim。
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
