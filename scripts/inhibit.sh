#!/bin/bash
# inhibit.sh — 包装 vendor/inhibit.sh：原脚本 echo 不解释 \u，会输出字面量，需转成真字形
D="$(dirname "$(readlink -f "$0")")"
out=$(bash "$D/vendor/inhibit.sh" "$@" 2>/dev/null)
printf '%s' "$out" | sed -e 's/\\uf023//g' -e 's/\\uf09c//g'
