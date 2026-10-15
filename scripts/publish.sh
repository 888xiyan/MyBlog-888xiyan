#!/usr/bin/env bash

set -euo pipefail

project_dir="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$project_dir"

pause_if_interactive() {
  if [[ "${PUBLISH_INTERACTIVE:-0}" == "1" ]]; then
    read -r -p "按 Enter 键关闭窗口…" </dev/tty || true
  fi
}

handle_error() {
  printf '\n发布失败：请检查上方错误信息。\n' >&2
  pause_if_interactive
}
trap handle_error ERR

if [[ -x "$project_dir/bin/hugo" ]]; then
  hugo_cmd="$project_dir/bin/hugo"
elif command -v hugo >/dev/null 2>&1; then
  hugo_cmd="$(command -v hugo)"
else
  printf '未找到 Hugo。请先安装 Hugo Extended，或恢复 bin/hugo。\n' >&2
  exit 1
fi

if [[ $# -gt 0 ]]; then
  commit_message="$*"
else
  commit_message="Publish blog update $(date '+%Y-%m-%d %H:%M')"
fi

printf '正在构建 Hugo 站点…\n'
"$hugo_cmd" --gc --minify

printf '正在暂存变更…\n'
git add -A

if git diff --cached --quiet; then
  printf '没有需要发布的变更。\n'
  pause_if_interactive
  exit 0
fi

printf '正在提交：%s\n' "$commit_message"
git commit -m "$commit_message"

printf '正在推送至 origin/main…\n'
git push origin main

printf '\n发布完成： https://888xiyan.github.io/MyBlog-888xiyan/\n'
pause_if_interactive
