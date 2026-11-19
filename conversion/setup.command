#!/bin/zsh
set -eu
cd -- "${0:A:h}"
uv_executable=$(command -v uv || true)
if [[ -z "$uv_executable" && -x /opt/homebrew/bin/uv ]]; then
  uv_executable=/opt/homebrew/bin/uv
fi
if [[ -z "$uv_executable" && -x /usr/local/bin/uv ]]; then
  uv_executable=/usr/local/bin/uv
fi
if [[ -z "$uv_executable" ]]; then
  print -u2 '需要安装 uv 以创建本地格式转换环境。'
  exit 1
fi
"$uv_executable" venv --python 3.12 .venv
"$uv_executable" pip install --python .venv/bin/python -r requirements.txt
