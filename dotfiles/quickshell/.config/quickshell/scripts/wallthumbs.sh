#!/bin/bash
# wallthumbs.sh — 壁纸缩略图缓存（供 quickshell 选择器网格）。
# 存放：~/.cache/by-mgr/wallthumbs/<stat-id>.jpg
# stat 口径与 theme-sync.sh 的 work-small 缓存一致（%d-%i-%s-%Y），
# 存在即最新；顺带清掉已删壁纸的孤儿缩略图。
# 用法: wallthumbs.sh list   # 逐行输出 JSON {name,url,thumb}，边生成边吐（网格渐进加载）
CACHE="$HOME/.cache/by-mgr/wall-thumbs"
SRC="$HOME/Pictures/wallpapers"
mkdir -p "$CACHE"

gen_thumb() {
  local src="$1" id="$2"
  local thumb="$CACHE/$id.jpg"
  if [ -s "$thumb" ]; then
    printf '%s' "$thumb"
    return 0
  fi
  if command -v ffmpeg &>/dev/null; then
    timeout 20 ffmpeg -y -loglevel error -i "$src" -vf "scale=360:-1" "$thumb" 2>/dev/null
  fi
  if [ ! -s "$thumb" ]; then
    python3 - "$src" "$thumb" 2>/dev/null <<'PY'
import sys
try:
    from PIL import Image
    img = Image.open(sys.argv[1]).convert('RGB')
    img.thumbnail((360, 360))
    img.save(sys.argv[2], 'JPEG', quality=82)
except Exception:
    pass
PY
  fi
  if [ -s "$thumb" ]; then
    printf '%s' "$thumb"
  else
    printf '%s' "$src"
  fi
}

declare -A needed=()
shopt -s nullglob nocaseglob
files=("$SRC"/*.jpg "$SRC"/*.jpeg "$SRC"/*.png "$SRC"/*.webp)
shopt -u nullglob nocaseglob
for src in "${files[@]}"; do
  [ -f "$src" ] || continue
  name=$(basename "$src")
  id=$(stat -c '%d-%i-%s-%Y' "$src" 2>/dev/null)
  [ -z "$id" ] && continue
  needed["$id.jpg"]=1
  thumb=$(gen_thumb "$src" "$id")
  esc=${name//\\/\\\\}; esc=${esc//\"/\\\"}
  printf '{"name":"%s","url":"file://%s","thumb":"file://%s"}\n' "$esc" "$src" "$thumb"
done

# 清孤儿
for old in "$CACHE"/*.jpg; do
  [ -f "$old" ] || continue
  b=$(basename "$old")
  [ -z "${needed[$b]}" ] && rm -f "$old"
done
