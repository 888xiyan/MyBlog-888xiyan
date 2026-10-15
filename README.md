# MyBlog-888xiyan

一个基于 Hugo Extended 和 PaperMod 的静态博客。

## 本地预览

```bash
./bin/hugo server --buildDrafts
```

浏览器打开 <http://localhost:1313>。

## 创建文章

```bash
./bin/hugo new content posts/文章名.md
```

将文章中的 `draft` 改为 `false` 后即可发布。

## 生产构建

```bash
./bin/hugo --gc --minify
```

生成的网站文件位于 `public/`，此目录已被 Git 忽略。

## GitHub Pages

仓库已将远程地址配置为 `git@github.com:888xiyan/MyBlog-888xiyan.git`。推送至 `main` 后，可在仓库的 GitHub Pages 设置中选择 GitHub Actions 作为发布源。
