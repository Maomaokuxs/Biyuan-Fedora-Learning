#!/bin/bash
# lib/editor.sh — 编辑器设置
set -e
editors=("nvim" "vim" "nano" "kate")
which_ok() { command -v "$1" &>/dev/null; }

if [ -n "$1" ]; then
    ed="$1"
    which_ok "$ed" || { echo "未安装: $ed" >&2; exit 1; }
    sudo update-alternatives --set editor "/usr/bin/$ed" 2>/dev/null || true
    git config --global core.editor "$ed" 2>/dev/null || true
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "\033[0;32m✅ 已设置默认编辑器为: $ed\033[0m"
    else
        echo "✅ 已设置默认编辑器为: $ed"
    fi
    exit 0
fi

echo "可选编辑器:"
for i in "${!editors[@]}"; do
    avail=" "; which_ok "${editors[i]}" && avail="✓"
    echo "  $((i+1))) [$avail] ${editors[i]}"
done
read -p "选择编号 (0 返回): " n < /dev/tty 2>/dev/null || read -p "选择编号 (0 返回): " n
[[ "$n" =~ ^[0-9]+$ ]] && [ "$n" -ge 1 ] && [ "$n" -le ${#editors[@]} ] || { echo "已取消"; exit 0; }
ed="${editors[$((n-1))]}"
which_ok "$ed" || { echo "未安装: $ed"; exit 1; }
sudo update-alternatives --set editor "/usr/bin/$ed" 2>/dev/null || true
git config --global core.editor "$ed" 2>/dev/null || true
if [ -z "${BY_MGR_QUIET:-}" ]; then
    echo -e "\033[0;32m✅ 已设置默认编辑器为: $ed\033[0m"
else
    echo "✅ 已设置默认编辑器为: $ed"
fi
