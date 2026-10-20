#!/bin/bash
# lib/snapshot.sh — 创建快照 (被 Rust UI 调用)
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"
LOG_FILE="$LOG_DIR/snapshot.log"
mkdir -p "$LOG_DIR"
echo "[$(date +%H:%M:%S)] snapshot START dotfiles=$DOTFILES_DIR" > "$LOG_FILE"

mkdir -p "$BACKUP_ROOT"
# 清理 1 小时前中断遗留的临时构建目录
find "$BACKUP_ROOT" -mindepth 1 -maxdepth 1 -name '.tmp-*' -mmin +60 -exec rm -rf {} + 2>/dev/null || true
date_tag=$(date +%Y%m%d_%H%M%S)
current_backup_dir="$BACKUP_ROOT/.tmp-$date_tag"
while [ -e "$BACKUP_ROOT/$date_tag" ] || [ -e "$current_backup_dir" ]; do
    sleep 1
    date_tag=$(date +%Y%m%d_%H%M%S)
    current_backup_dir="$BACKUP_ROOT/.tmp-$date_tag"
done
mkdir -p "$current_backup_dir"
backed_any=false
missing=""
failed=""
# 仅输出 文件 -> 目录 精简信息，供 TUI 状态栏显示
# 清理历史遗留的 waybar 桥接软链（防 stow absolute symlink 冲突）
[ -d "$DOTFILES_DIR/waybar/.cache" ] && trash_move "$DOTFILES_DIR/waybar/.cache" || true
for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
    src=$(get_target_path "$module")
    if [ ! -e "$src" ] && [ ! -L "$src" ]; then
        missing="$missing $module"
        continue
    fi
    if true; then
        [ -d "$src" ] && [ ! -L "$src" ] && [ -z "$(ls -A "$src" 2>/dev/null)" ] && continue
        rel_path="${src#$HOME/}"
        dest="$current_backup_dir/$rel_path"
        mkdir -p "$(dirname "$dest")"
        # by-mgr 特殊处理：排除 backup 目录避免自包含递归
        if [ "$module" = "by-mgr" ] && [ -d "$src" ]; then
            mkdir -p "$dest"
            candidates=0
            mod_ok=false
            for f in "$src"/*; do
                [ -e "$f" ] || continue
                bn=$(basename "$f")
                [ "$bn" = "backup" ] && continue
                [ "$bn" = "trash" ] && continue
                candidates=$((candidates+1))
                if cp -aL "$f" "$dest/" 2>/dev/null; then
                    echo "$rel_path/$bn -> $dest/$bn" | tee -a "$LOG_FILE"
                    backed_any=true
                    mod_ok=true
                fi
            done
            if [ "$mod_ok" = false ] && [ "$candidates" -gt 0 ]; then
                failed="$failed $module"
            fi
            # by-mgr 下无可备份文件时视为正常（保持旧语义）
            [ "$candidates" -eq 0 ] && backed_any=true
            continue
        fi
        if cp -aL "$src" "$dest" 2>/dev/null; then
            echo "$rel_path -> $current_backup_dir/$rel_path" | tee -a "$LOG_FILE"
            backed_any=true
        else
            failed="$failed $module"
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
if [ -n "$missing" ]; then
    echo "⚠️ 以下模块的配置路径不存在，未备份:$missing" | tee -a "$LOG_FILE"
fi
if [ -n "$failed" ]; then
    echo "⚠️ 以下模块备份失败:$failed" | tee -a "$LOG_FILE"
fi
if [ "$backed_any" = true ]; then
    # 生成文件清单（路径+sha256）并立即回查校验
    (cd "$current_backup_dir" && find . -type f ! -name 'manifest.txt' ! -name '.bymgr-meta.json' -print0 | sort -z | xargs -0 -r sha256sum > manifest.txt 2>/dev/null) || true
    if (cd "$current_backup_dir" && sha256sum -c manifest.txt >/dev/null 2>&1); then
        touch "$current_backup_dir/.bymgr-verified"
        echo "[$(date +%H:%M:%S)] verify OK $date_tag" >> "$LOG_FILE"
    else
        echo "⚠️ 快照自检未通过（清单校验失败）: $date_tag" | tee -a "$LOG_FILE"
    fi
    # 原子改名：完整快照才出现在正式目录
    mv "$current_backup_dir" "$BACKUP_ROOT/$date_tag"
    current_backup_dir="$BACKUP_ROOT/$date_tag"
    echo "✅ $date_tag" | tee -a "$LOG_FILE"
    echo "[$(date +%H:%M:%S)] snapshot DONE $date_tag $current_backup_dir" >> "$LOG_FILE"
else
    rm -rf "$current_backup_dir"
    echo "无需备份" | tee -a "$LOG_FILE"
    echo "[$(date +%H:%M:%S)] snapshot EMPTY" >> "$LOG_FILE"
    exit 1
fi
