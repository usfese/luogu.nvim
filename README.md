# luogu.nvim

基于 [kawre/leetcode.nvim](https://github.com/kawre/leetcode.nvim) 的洛谷刷题插件，保留上游的菜单、题目窗口和控制台布局。

## 依赖

- Neovim 0.10+
- `curl`
- `nvim-lua/plenary.nvim`
- `MunifTanjim/nui.nvim`
- `nvim-telescope/telescope.nvim`

## 安装

```lua
{
  "usfese/luogu.nvim",
  cmd = "Luogu",
  dependencies = {
    "nvim-lua/plenary.nvim",
    "MunifTanjim/nui.nvim",
    "nvim-telescope/telescope.nvim",
  },
  config = function() require("luogu").setup() end,
}
```

`:Luogu` 打开菜单；`:Luogu list` 打开题库；`:Luogu open P1001` 打开题目；`:Luogu login` 输入洛谷 Cookie；`:Luogu submit` 提交；`:Luogu desc` 切换题面。

题库使用 Telescope 模糊搜索：输入题号或标题，选择后按回车打开。题目索引会在后台逐页同步并缓存到本地；首次同步期间也可以搜索，未完成的索引会在下次继续。

题面以 Markdown 缓冲区显示，可使用现有 Markdown 高亮或 `render-markdown.nvim` 美化。常见数学符号会转换为 Unicode；复杂公式保留 LaTeX 写法，渲染取决于 Markdown 插件及其依赖。

登录时粘贴浏览器请求头中的 Cookie 值或完整的 `Cookie: …` 行；输入会明文显示。验证成功后 Cookie 明文保存在 Neovim 数据目录的 `luogu/cookie` 文件中，权限为 0600。

洛谷没有公开 API，站点接口可能变更。洛谷不提供与 LeetCode 相同的自定义输入运行接口。

## 许可

本项目派生自 [kawre/leetcode.nvim](https://github.com/kawre/leetcode.nvim)，其代码遵循 MIT 许可证；原版权和许可文本保留在 `LICENSE`。
