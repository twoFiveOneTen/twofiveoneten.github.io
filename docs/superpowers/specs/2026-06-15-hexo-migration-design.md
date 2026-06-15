# Jekyll → Hexo 迁移设计

日期：2026-06-15
状态：已批准，待实施

## 背景

当前仓库是 GitHub Pages 上的 Jekyll 博客（分支 `gh-pages`，自定义域名 `note.zkk.me`），使用 `jekyll-theme-yat` 主题，包含 71 篇文章（2018–2022）、166MB 图片资源、自定义 banner、关于/分类/404 页面，以及通过 GitHub Actions 部署到 GitHub Pages 的工作流。

需求：将整个仓库从 Jekyll 迁移到 Hexo，保持文章 URL、自定义域名、视觉效果、部署方式不变。

## 目标

- 静态站点生成器从 Jekyll 切换到 Hexo（使用 Fluid 主题）
- 所有文章 permalink 保持不变（`/0x0000.html` 等）
- 自定义域名 `note.zkk.me` 保持不变
- 继续通过 GitHub Actions 部署到 `gh-pages` 分支
- 图片资源零迁移成本（绝对路径引用不变）
- 启用本地搜索
- 不引入评论、统计等外部依赖

## 仓库结构（迁移后）

```
twofiveoneten.github.io/
├── package.json                    # 新增：Hexo 依赖
├── _config.yml                     # 重写：Jekyll → Hexo 配置
├── _config.fluid.yml               # 新增：Fluid 主题配置
├── .github/
│   └── workflows/
│       └── pages.yml               # 重写：Node 版部署工作流（替换原 jekyll.yml）
├── themes/
│   └── fluid/                      # 新增：Fluid 主题（npm 安装）
├── source/                         # 新增：Hexo 源目录
│   ├── _posts/                     # 迁移自 _posts/，71 篇不变
│   ├── about/index.md              # 迁移自 about.markdown
│   ├── categories/index.md         # 迁移自 categories.html
│   ├── 404.html                    # 迁移自 404.html
│   ├── img/                        # 迁移自 img/，166MB 原样保留
│   ├── CNAME                       # 保留 note.zkk.me
│   └── favicon.ico                 # 沿用
├── public/                         # 新增：Hexo 生成产物（.gitignore 忽略）
├── .gitignore                      # 更新
└── docs/superpowers/specs/         # 设计文档位置
```

**删除的文件/目录**：
- `Gemfile`、`Gemfile.lock`
- `_includes/custom-head.html`
- `assets/css/custom.css`（全部被注释，无实际样式）
- `_site/`、`.jekyll-cache/`、`.venv/`
- `typechoToJekyll.swift`（一次性迁移脚本，已无用）
- `.github/workflows/jekyll.yml`

## Hexo 主配置

`_config.yml`：

```yaml
title: zkk's blog
subtitle: '分享点滴学习，记录成长足迹'
description: '我的个人在线笔记本'
author: zkk
language: zh-CN
timezone: Asia/Shanghai
url: https://note.zkk.me
root: /
permalink_defaults:
permalink: :year/:month/:day/:title/
theme: fluid
```

文章 frontmatter 中的 `permalink: /0x0000.html` 会优先生效，覆盖上面的默认格式。

## Fluid 主题配置

`_config.fluid.yml`：

```yaml
banner:
  home:
    img: /img/global/bg.png
    heading: '欢迎来到我的笔记本'
    subheading: '分享点滴学习，记录成长足迹'

# 启用本地搜索
search:
  enable: true
  path: /local-search.xml

# 中文字数统计、代码高亮等沿用主题默认
```

## package.json

```json
{
  "scripts": {
    "build": "hexo generate",
    "serve": "hexo serve",
    "clean": "hexo clean"
  },
  "dependencies": {
    "hexo": "^7.3.0",
    "hexo-theme-fluid": "^1.9.4",
    "hexo-generator-search": "^0.2.1",
    "hexo-generator-feed": "^3.0.0",
    "hexo-renderer-marked": "^6.0.0"
  }
}
```

## 部署工作流

`.github/workflows/pages.yml`：

```yaml
name: Deploy Hexo site to Pages
on:
  push:
    branches: [gh-pages]
  workflow_dispatch:

permissions:
  contents: read
  pages: write
  id-token: write

concurrency:
  group: pages
  cancel-in-progress: false

jobs:
  build:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: actions/setup-node@v4
        with:
          node-version: 20
          cache: npm
      - run: npm ci
      - run: npx hexo generate
      - uses: actions/configure-pages@v5
      - uses: actions/upload-pages-artifact@v3
        with:
          path: public
  deploy:
    needs: build
    runs-on: ubuntu-latest
    environment:
      name: github-pages
    steps:
      - id: deployment
        uses: actions/deploy-pages@v4
```

构建产物从 `_site/` 改为 `public/`。

## Frontmatter 兼容性

Jekyll frontmatter 中使用的字段在 Hexo 中全部受支持：

| 字段 | Hexo 支持 | 处理 |
|------|----------|------|
| `layout` | 是 | 保留 |
| `title` | 是 | 保留 |
| `date` | 是 | 保留 |
| `categories` | 是 | 保留 |
| `tags` | 是 | 保留 |
| `permalink` | 是 | 保留，优先于 `_config.yml` 默认 |

**摘要分隔符**：Hexo 默认使用 `<!-- more -->`（带空格），Jekyll 使用 `<!--more-->`。用一次性的 sed 命令批量替换：

```bash
find source/_posts -name '*.md' -exec sed -i '' 's/<!--more-->/<!-- more -->/g' {} +
```

## 执行步骤

1. 创建工作分支 `feature/hexo-migration`
2. 创建 `docs/superpowers/specs/` 目录，写入设计文档（本文件）
3. 写入 `package.json`、`_config.yml`、`_config.fluid.yml`
4. `npm install` 安装本地依赖
5. 创建 `source/` 目录结构：
   - `mkdir -p source/_posts`
   - `mv _posts/* source/_posts/`
   - `sed -i '' 's/<!--more-->/<!-- more -->/g' source/_posts/*.md`
   - `mkdir -p source/about && mv about.markdown source/about/index.md`
   - `mkdir -p source/categories && mv categories.html source/categories/index.md`
   - `mv 404.html source/404.html`
   - `mv img source/img`
   - `mv CNAME source/CNAME`
   - `mv favicon.ico source/favicon.ico`
6. 删除 Jekyll 残留：
   - `rm -rf Gemfile Gemfile.lock _includes _site .jekyll-cache .venv`
   - `rm -f typechoToJekyll.swift assets/css/custom.css`
   - `rm .github/workflows/jekyll.yml`
7. 重写 `.github/workflows/pages.yml`
8. 更新 `.gitignore`，加入 `node_modules/`、`public/`、`.DS_Store`
9. 本地验证：`npx hexo clean && npx hexo server` → 浏览器抽样检查
10. 合并 `feature/hexo-migration` 回 `gh-pages`，推送 → Actions 自动部署
11. 线上验证（见下）

## 验证清单

迁移后必须满足：

- [ ] `npx hexo generate` 无错误，生成 71 篇 HTML 文章
- [ ] 抽样 5 篇文章的 permalink 与原 Jekyll 一致（如 `/0x0000.html`、`/0x0045.html`）
- [ ] 抽样文章的 `/img/...` 图片 URL 仍然能正常加载
- [ ] 首页 banner（`/img/global/bg.png`）正常显示
- [ ] 关于页、分类页可访问
- [ ] 404 页可触发
- [ ] 本地搜索框可用
- [ ] `note.zkk.me` 域名访问正常
- [ ] GitHub Actions 部署成功（无构建错误）

## 不在范围内

- 评论系统（暂不引入）
- 访问统计（暂不引入）
- 文章 URL 重定向脚本（permalink 完全保留，不需要）
- 主题深度定制（用 Fluid 默认配置即可）
- 旧 Jekyll 站点的双轨并行（一次性切换）
