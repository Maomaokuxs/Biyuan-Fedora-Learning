#!/bin/bash
# lib/snapshot.sh — 创建快照 (被 Rust UI 调用)
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"
LOG_FILE="$LOG_DIR/snapshot.log"
mkdir -p "$LOG_DIR"
echo "[$(date +%H:%M:%S)] snapshot START dotfiles=$DOTFILES_DIR" > "$LOG_FILE"

date_tag=$(date +%Y%m%d_%H%M%S)
current_backup_dir="$BACKUP_ROOT/$date_tag"
mkdir -p "$current_backup_dir"
backed_any=false
# 仅输出 文件 -> 目录 精简信息，供 TUI 状态栏显示
# 清理历史遗留的 waybar 桥接软链（防 stow absolute symlink 冲突）
[ -d "$DOTFILES_DIR/waybar/.cache" ] && rm -rf "$DOTFILES_DIR/waybar/.cache" 2>/dev/null || true
for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
    src=$(get_target_path "$module")
    if [ -e "$src" ] || [ -L "$src" ]; then
        [ -d "$src" ] && [ ! -L "$src" ] && [ -z "$(ls -A "$src" 2>/dev/null)" ] && continue
        rel_path="${src#$HOME/}"
        dest="$current_backup_dir/$rel_path"
        mkdir -p "$(dirname "$dest")"
        # by-mgr 特殊处理：排除 backup 目录避免自包含递归
        if [ "$module" = "by-mgr" ] && [ -d "$src" ]; then
            mkdir -p "$dest"
            for f in "$src"/*; do
                [ -e "$f" ] || continue
                bn=$(basename "$f")
                [ "$bn" = "backup" ] && continue
                cp -aL "$f" "$dest/" 2>/dev/null && echo "$rel_path/$bn -> $dest/$bn" | tee -a "$LOG_FILE" && backed_any=true
            done
            # 若 by-mgr 下无非 backup 文件，仍视为已备份
            [ "$backed_any" = true ] || backed_any=true
            continue
        fi
        if cp -aL "$src" "$dest" 2>/dev/null; then
            echo "$rel_path -> $current_backup_dir/$rel_path" | tee -a "$LOG_FILE"
            backed_any=true
        fi
    fi
done
# 追加 .cache 配色与壁纸状态（不存在则跳过，无 waypaper 亦不异常）
for p in "$HOME/.cache/by-mgr/hellwal" "$HOME/.cache/by-mgr/last-wallpaper"; do
    [ -e "$p" ] || continue
    rel="${p#$HOME/}"
    dest="$current_backup_dir/$rel"
    mkdir -p "$(dirname "$dest")"
    if [ -d "$p" ] && [ ! -L "$p" ]; then
        cp -a "$p" "$dest" 2>/dev/null && echo "$rel -> $dest" | tee -a "$LOG_FILE" && backed_any=true
    elif [ -f "$p" ] || [ -L "$p" ]; then
        cp -aL "$p" "$dest" 2>/dev/null && echo "$rel -> $dest" | tee -a "$LOG_FILE" && backed_any=true
    fi
done
if [ "$backed_any" = true ]; then
    echo "✅ $date_tag" | tee -a "$LOG_FILE"
    echo "[$(date +%H:%M:%S)] snapshot DONE $date_tag $current_backup_dir" >> "$LOG_FILE"
else
    rm -rf "$current_backup_dir"
    echo "无需备份" | tee -a "$LOG_FILE"
    echo "[$(date +%H:%M:%S)] snapshot EMPTY" >> "$LOG_FILE"
    exit 1
fi
