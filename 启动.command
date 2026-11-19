#!/bin/zsh
set -eu
patcher_root="${0:A:h}"
launcher="$patcher_root/VOCALOID7 Patcher.app/Contents/MacOS/Launcher"
if [[ ! -x "$launcher" ]]; then
  print -u2 '请先运行 build.command 构建启动器。'
  exit 1
fi
exec "$launcher"
