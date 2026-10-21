#!/bin/bash
# lib/restore.sh — 历史还原
# 用法: restore.sh [last|-1|编号|时间戳]
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"
LOG_FILE="$LOG_DIR/restore.log"
mkdir -p "$LOG_DIR"
echo "[$(date +%H:%M:%S)] restore START arg=${1:-<interactive>} dotfiles=$DOTFILES_DIR" > "$LOG_FILE"

mapfile -t time_list < <(list_snapshots | tac)
if [ ${#time_list[@]} -eq 0 ]; then
    echo -e "${RED}❌ 无历史备份！${NC}" >&2
    exit 1
fi

arg="${1:-}"
selected_time=""
if [[ "$arg" == "last" || "$arg" == "-1" ]]; then
    selected_time="${time_list[0]}"
elif [[ "$arg" =~ ^[0-9]+$ ]] && [ "$arg" -ge 1 ] && [ "$arg" -le ${#time_list[@]} ]; then
    selected_time="${time_list[$((arg-1))]}"
elif [ -n "$arg" ]; then
    for t in "${time_list[@]}"; do
        if [[ "$(basename "$t")" == "$arg" ]]; then selected_time="$t"; break; fi
    done
    [ -z "$selected_time" ] && { echo -e "${RED}❌ 未找到快照: $arg${NC}" >&2; exit 1; }
else
    echo "可用快照:"
    for i in "${!time_list[@]}"; do echo "  $((i+1))) $(basename "${time_list[i]}")"; done
    read -p "选择快照编号 (1-${#time_list[@]}, 0 取消): " choice < /dev/tty
    [[ "$choice" =~ ^[0-9]+$ ]] && [ "$choice" -ge 1 ] && [ "$choice" -le ${#time_list[@]} ] || { echo "已取消"; exit 0; }
    selected_time="${time_list[$((choice-1))]}"
fi

if [ -z "${BY_MGR_QUIET:-}" ]; then
    echo -e "${BLUE}>> 正在从 $(basename "$selected_time") 还原...${NC}" | tee -a "$LOG_FILE"
fi
echo "[$(date +%H:%M:%S)] restore selected=$selected_time" >> "$LOG_FILE"
restored=0
failed=0
failed_list=""
# stow 可用性（懒检查，只查一次）：stow 还原分支强依赖它，缺失时必须判失败而非假成功
stow_state="unknown"
have_stow() {
    if [ "$stow_state" = "unknown" ]; then
        if command -v stow &>/dev/null; then stow_state="yes"; else stow_state="no"; fi
    fi
    [ "$stow_state" = "yes" ]
}
for mod in $(ls "$DOTFILES_DIR" 2>/dev/null); do
    mod_target=$(get_target_path "$mod")
    backup_src="${selected_time}/${mod_target#$HOME/}"
    [ -e "$backup_src" ] || { echo "[$(date +%H:%M:%S)] skip $mod (no backup_src)" >> "$LOG_FILE"; continue; }
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "  ${CYAN}还原: $mod${NC}" | tee -a "$LOG_FILE"
    else
        echo "[$(date +%H:%M:%S)] restore $mod" >> "$LOG_FILE"
    fi
    target=$(get_target_path "$mod")
    mod_ok=false
    have_stow && (cd "$DOTFILES_DIR" && stow -D -t ~ "$mod" 2>/dev/null || true)
    # 判断部署方式：快照中若该模块为软链则用 stow 还原，物理则本地还原
    use_stow=false
    if [ -L "$target" ]; then use_stow=true; fi
    if [ "$mod" = "by-mgr" ]; then
        # by-mgr 特殊：保留 backup 目录，避免自删除
        mkdir -p "$target"
        mod_copied=0
        for f in "$backup_src"/*; do
            [ -e "$f" ] || continue
            bn=$(basename "$f")
            [ "$bn" = "backup" ] && continue
            [ "$bn" = "trash" ] && continue
            cp -a "$f" "$target/" 2>/dev/null && mod_copied=$((mod_copied+1)) || true
        done
        # 清理目标中不在备份中的旧文件（除 backup 外）
        for f in "$target"/*; do
            [ -e "$f" ] || continue
            bn=$(basename "$f")
            [ "$bn" = "backup" ] && continue
            [ "$bn" = "trash" ] && continue
            [ -e "$backup_src/$bn" ] || trash_move "$f"
        done
        if [ "$mod_copied" -gt 0 ] || [ -z "$(ls -A "$backup_src" 2>/dev/null)" ]; then
            mod_ok=true
        fi
    elif [ "$use_stow" = true ]; then
        # stow 还原：快照内容写回仓库对应位置后重新 stow 链接
        # stow 缺失或链接未生成一律判失败，不再吞错误假成功
        if ! have_stow; then
            echo "[$(date +%H:%M:%S)] FAIL $mod: 需要 stow 但未安装" >> "$LOG_FILE"
        else
            clean_target "$target"
            rel_target="${target#$HOME/}"
            # 写回位置即 stow 镜像路径：仓库/<模块>/<目标相对路径>，目录拷内容、文件拷本体
            if [ -d "$backup_src" ]; then
                mkdir -p "$DOTFILES_DIR/$mod/$rel_target"
                cp -a "$backup_src/." "$DOTFILES_DIR/$mod/$rel_target/" 2>/dev/null || true
            else
                mkdir -p "$DOTFILES_DIR/$mod/$(dirname "$rel_target")"
                cp -a "$backup_src" "$DOTFILES_DIR/$mod/$rel_target" 2>/dev/null || true
            fi
            if (cd "$DOTFILES_DIR" && stow -t ~ "$mod" >> "$LOG_FILE" 2>&1) && { [ -e "$target" ] || [ -L "$target" ]; }; then
                mod_ok=true
            else
                echo "[$(date +%H:%M:%S)] FAIL $mod: stow 执行失败或目标未生成" >> "$LOG_FILE"
            fi
        fi
    else
        clean_target "$target"
        if [ -d "$backup_src" ]; then
            if mkdir -p "$target" && cp -a "$backup_src/." "$target/"; then mod_ok=true; fi
        else
            if mkdir -p "$(dirname "$target")" && cp -a "$backup_src" "$target"; then mod_ok=true; fi
        fi
    fi
    if [ "$mod_ok" = true ]; then
        restored=$((restored+1))
    else
        failed=$((failed+1))
        failed_list="$failed_list $mod"
    fi
    echo "[$(date +%H:%M:%S)] restored $mod -> $target" >> "$LOG_FILE"
done
# 追加 .cache 配色与壁纸还原（不存在则跳过）
for p in ".cache/by-mgr/hellwal" ".cache/by-mgr/last-wallpaper"; do
    backup_src="${selected_time}/$p"
    [ -e "$backup_src" ] || continue
    target="$HOME/$p"
    mkdir -p "$(dirname "$target")"
    if [ -d "$backup_src" ]; then
        trash_move "$target"
        cp -a "$backup_src" "$target" 2>/dev/null && echo "[$(date +%H:%M:%S)] restored $p" >> "$LOG_FILE" && restored=$((restored+1))
    else
        cp -aL "$backup_src" "$target" 2>/dev/null && echo "[$(date +%H:%M:%S)] restored $p" >> "$LOG_FILE" && restored=$((restored+1))
    fi
done
# 壁纸生效：仅 awww 渲染，不修改 waypaper 配置
if [ -f "$HOME/.cache/by-mgr/last-wallpaper" ]; then
    WALLPAPER=$(cat "$HOME/.cache/by-mgr/last-wallpaper" 2>/dev/null)
    if [ -n "$WALLPAPER" ] && [ -f "$WALLPAPER" ]; then
        if [ -n "${WAYLAND_DISPLAY:-}" ] && command -v awww &>/dev/null; then
            awww img "$WALLPAPER" --transition-type random --transition-duration 1 2>/dev/null || true
            echo "[$(date +%H:%M:%S)] awww triggered $WALLPAPER" >> "$LOG_FILE"
        else
            echo "[$(date +%H:%M:%S)] awww skipped (no Wayland/awww)" >> "$LOG_FILE"
        fi
    fi
fi
echo "[$(date +%H:%M:%S)] restore DONE restored=$restored failed=$failed" >> "$LOG_FILE"
if [ "$failed" -gt 0 ]; then
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${RED}⚠️ 还原结束：$restored 个成功，$failed 个失败:$failed_list${NC}" | tee -a "$LOG_FILE"
    else
        echo "⚠️ 还原结束：$restored 个成功，$failed 个失败:$failed_list" | tee -a "$LOG_FILE"
    fi
    exit 1
fi
if [ -z "${BY_MGR_QUIET:-}" ]; then
    echo -e "${GREEN}✅ 还原完成！共 $restored 模块${NC}" | tee -a "$LOG_FILE"
else
    echo "✅ $restored" | tee -a "$LOG_FILE"
fi
