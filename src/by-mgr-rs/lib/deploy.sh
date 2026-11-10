#!/bin/bash
# lib/deploy.sh — 部署配置
# 用法: deploy.sh <stow|local> (必须明确指定，无默认)
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

mode="${1:-}"
if [ -z "$mode" ]; then
    echo -e "${RED}❌ 用法: deploy.sh stow|local (必须明确指定模式)${NC}" >&2
    exit 1
fi
if [ "$mode" != "stow" ] && [ "$mode" != "local" ]; then
    echo -e "${RED}❌ 未知部署模式: $mode (可用 stow|local)${NC}" >&2
    exit 1
fi
# 执行前检查：stow 模式必须已安装 stow
if [ "$mode" = "stow" ] && ! command -v stow &>/dev/null; then
    echo -e "${RED}❌ stow 未安装，无法执行 stow 部署${NC}" >&2
    echo -e "${YELLOW}请先执行: sudo dnf install -y stow${NC}" >&2
    echo -e "${CYAN}或改用本地模式: by-mgr deploy local${NC}" >&2
    exit 1
fi
mkdir -p "$LOG_DIR"
LOG_FILE="$LOG_DIR/deploy.log"
failed=0
clean_count=0  # stow 模式下逐文件比对后无变化的模块数
echo "[$(date +%H:%M:%S)] deploy START mode=$mode" > "$LOG_FILE"
if [ -z "${BY_MGR_QUIET:-}" ]; then
    echo -e "\n${BLUE}>> 正在部署配置 (${mode})...${NC}" | tee -a "$LOG_FILE"
else
    echo ">> 正在部署配置 ($mode)..." >> "$LOG_FILE"
fi
# 逐文件判定某模块是否已按 stow 正确部署（借鉴 biyuan-niri-deploy 的做法，
# 按重复使用的要求改过：只判定、不动手；动手仍走 by-mgr 自己的 trash/日志）。
# 每个源文件在 $HOME 下的对应位置都已是指向它的链接（readlink -f 比对，
# 能认出 stow 目录折叠），且模块目标根下没有断裂链接，才算干净。
# 干净的模块直接跳过，重复部署零动作；任一文件不对就返回 1，走全量路径。
module_stow_clean() {
    local mod="$1"
    local mod_dir="$DOTFILES_DIR/$mod"
    [ -d "$mod_dir" ] || return 1
    local src_file rel target src_canon
    while IFS= read -r -d '' src_file; do
        rel="${src_file#$mod_dir/}"
        target="$HOME/$rel"
        # 断裂链接：无内容可保，须走全量路径清理
        if [ -L "$target" ] && [ ! -e "$target" ]; then
            return 1
        fi
        if [ -e "$target" ]; then
            src_canon=$(readlink -f "$src_file" 2>/dev/null || echo "$src_file")
            [ "$(readlink -f "$target" 2>/dev/null)" = "$src_canon" ] || return 1
        else
            return 1
        fi
    done < <(find "$mod_dir" \( -type f -o -type l \) -print0 2>/dev/null)
    # 模块目标根下有断裂链接时也不算干净（例如仓库删了文件留下的旧链）；
    # 目标根本身就是链接时（stow 目录折叠）整棵树即仓库内容，无须再查。
    local root
    root=$(get_target_path "$mod")
    if [ -d "$root" ] && [ ! -L "$root" ]; then
        if find "$root" -xtype l -print -quit 2>/dev/null | grep -q .; then
            return 1
        fi
    fi
    return 0
}

# 清理历史遗留的 waybar 桥接软链（防 stow absolute symlink 冲突）
[ -d "$DOTFILES_DIR/waybar/.cache" ] && trash_move "$DOTFILES_DIR/waybar/.cache" || true
for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
    [[ "$module" == "bash" ]] && continue
    [[ "$module" == "by-mgr" ]] && continue  # by-mgr 独立目录，不 stow
    target=$(get_target_path "$module")
    if [ "$mode" = "stow" ]; then
        # 逐文件比对 fast-path：已正确部署的模块直接跳过，不动 stow -D/trash/stow；
        # 任一文件不对（缺失、断裂、指错）就走下面的全量路径，原有安全语义不变。
        # 注意：模块目标根下用户自己加的文件不在判定内，fast-path 会留着它们
        # （原来全量路径会把整个目标目录 trash 走，重复部署时反而丢东西）。
        if module_stow_clean "$module"; then
            clean_count=$((clean_count + 1))
            echo "[跳过] $module (已是最新)" >> "$LOG_FILE"
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  $module" | tee -a "$LOG_FILE"
            else
                echo "  $module" >> "$LOG_FILE"
            fi
            continue
        fi
        # 兼容处理：starship 的 starship_base.toml 为模板，local 模式残留的实体会阻塞 stow
        if [ "$module" = "starship" ] && [ -f "$HOME/.config/starship_base.toml" ] && [ ! -L "$HOME/.config/starship_base.toml" ]; then
            trash_move "$HOME/.config/starship_base.toml"
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  ${YELLOW}[兼容] 已清理残留 starship_base.toml${NC}" | tee -a "$LOG_FILE"
            else
                echo "  [兼容] 已清理残留 starship_base.toml" >> "$LOG_FILE"
            fi
        fi
        if [ "$module" = "plasma-apply-colorscheme" ] && [ -f "$HOME/.local/bin/plasma-apply-colorscheme" ] && [ ! -L "$HOME/.local/bin/plasma-apply-colorscheme" ]; then
            trash_move "$HOME/.local/bin/plasma-apply-colorscheme"
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  ${YELLOW}[兼容] 已清理残留 plasma-apply-colorscheme${NC}" | tee -a "$LOG_FILE"
            else
                echo "  [兼容] 已清理残留 plasma-apply-colorscheme" >> "$LOG_FILE"
            fi
        fi
        # 先尝试回收旧链接，失败不隐藏错误（便于排查）
        (cd "$DOTFILES_DIR" && stow -D -t "$HOME" "$module" >> "$LOG_FILE" 2>&1 || true)
        # stow 前彻底清理本地实文件残留（fastfetch 等单文件冲突）
        if [ -e "$target" ] || [ -L "$target" ]; then
            trash_move "$target"
        fi
        clean_target "$target"
        if (cd "$DOTFILES_DIR" && stow -v -t "$HOME" "$module" >> "$LOG_FILE" 2>&1); then
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  $module" | tee -a "$LOG_FILE"
            else
                echo "  $module" >> "$LOG_FILE"
            fi
        else
            failed=$((failed+1))
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  ${RED}[❌ stow 失败] $module (已记录到 $LOG_FILE)${NC}" | tee -a "$LOG_FILE"
            else
                echo "[❌ stow 失败] $module" | tee -a "$LOG_FILE"
            fi
        fi
    else
        # 本地部署：首次覆盖已存在目标前自动创建一次快照（不询问）；BY_MGR_FORCE=1 跳过备份
        if [ -e "$target" ] || [ -L "$target" ]; then
            if [ -z "${deploy_backup_done:-}" ]; then
                deploy_backup_done=1
                if [ "${BY_MGR_FORCE:-}" = "1" ]; then
                    if [ -z "${BY_MGR_QUIET:-}" ]; then
                        echo -e "${CYAN}>> --force：跳过部署前快照，直接覆盖...${NC}" | tee -a "$LOG_FILE"
                    else
                        echo "[本地部署] --force 跳过部署前快照，直接覆盖" >> "$LOG_FILE"
                    fi
                else
                    if [ -z "${BY_MGR_QUIET:-}" ]; then
                        echo -e "${BLUE}>> 部署前自动创建快照...${NC}" | tee -a "$LOG_FILE"
                    else
                        echo "[本地部署] 部署前自动创建快照" >> "$LOG_FILE"
                    fi
                    bash "$SCRIPT_DIR/snapshot.sh" 2>&1 | tee -a "$LOG_FILE"
                    if [ "${PIPESTATUS[0]}" -eq 0 ]; then
                        if [ -z "${BY_MGR_QUIET:-}" ]; then
                            echo -e "${GREEN}✅ 快照已创建，继续本地部署...${NC}" | tee -a "$LOG_FILE"
                        fi
                    else
                        echo -e "${YELLOW}⚠️  快照创建失败，继续部署（本次覆盖无备份）${NC}" | tee -a "$LOG_FILE"
                    fi
                fi
            fi
        fi
        (cd "$DOTFILES_DIR" && stow -D -t "$HOME" "$module" 2>/dev/null || true)
        clean_target "$target"
        # 与 stow 布局一致：模块根即家目录镜像，整树复制
        # （旧三分支只拷 .config 的情况会漏掉 .local 等其余部分）
        # 复制结果必须校验：cp 失败或目标未生成都判模块失败，走结尾的失败汇总，不假报 Local
        copy_ok=false
        if cp -a "$DOTFILES_DIR/$module/." "$HOME/" >> "$LOG_FILE" 2>&1 && [ -e "$target" ]; then
            copy_ok=true
        fi
        if [ "$copy_ok" = true ]; then
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  $module" | tee -a "$LOG_FILE"
            else
                echo "  $module" >> "$LOG_FILE"
            fi
        else
            failed=$((failed+1))
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  ${RED}[❌ 复制失败] $module (已记录到 $LOG_FILE)${NC}" | tee -a "$LOG_FILE"
            else
                echo "[❌ 复制失败] $module" | tee -a "$LOG_FILE"
            fi
        fi
    fi
done

# 模板同步（仓库 → 本地）
for src in "$DOTFILES_DIR/starship/.config/starship_base.toml" "$DOTFILES_DIR/mako/.config/mako/config_base"; do
    [ -f "$src" ] || continue
    dst="$HOME/.config/by-mgr/templates/$(basename "$src")"
    if [ ! -f "$dst" ]; then
        mkdir -p "$(dirname "$dst")"
        # 优先尝试链接，失败则复制
        ln -sfn "$src" "$dst" 2>/dev/null || cp -aL "$src" "$dst" 2>/dev/null || true
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo -e "${CYAN}  [模板] $(basename "$src") -> $dst${NC}" | tee -a "$LOG_FILE"
        else
            echo "  [模板] $(basename "$src") -> $dst" >> "$LOG_FILE"
        fi
    fi
done

# 触发配色（若存在 theme-sync.sh）
WALLPAPER=$(swww query 2>/dev/null | grep -oP 'image: \K.*' | head -1 || true)
[ -z "$WALLPAPER" ] && WALLPAPER=$(awww query 2>/dev/null | grep -oP 'image: \K.*' | head -1 || true)
if [ -n "$WALLPAPER" ] && [ -f "$HOME/.config/niri/scripts/theme-sync.sh" ]; then
    # 配色管线输出统一缩进成一组（明细同时进日志），不再与部署行混排
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${BLUE}>> 正在同步主题配色...${NC}" | tee -a "$LOG_FILE"
        bash "$HOME/.config/niri/scripts/theme-sync.sh" "$WALLPAPER" 2>&1 | sed 's/^\(.\)/  \1/' | tee -a "$LOG_FILE" || true
    else
        bash "$HOME/.config/niri/scripts/theme-sync.sh" "$WALLPAPER" >> "$LOG_FILE" 2>&1 || true
    fi
fi
if [ "$failed" -gt 0 ]; then
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${RED}❌ 部署完成，${failed} 个模块失败 (详见 $LOG_FILE)${NC}" | tee -a "$LOG_FILE"
    else
        echo "❌ 部署完成，${failed} 个模块失败" | tee -a "$LOG_FILE"
    fi
    exit 1
else
    if [ "$mode" = "stow" ] && [ "$clean_count" -gt 0 ]; then
        echo "✅ 部署完成 ($mode)：${clean_count} 个模块无变化" | tee -a "$LOG_FILE"
    else
        echo "✅ 部署完成 ($mode)" | tee -a "$LOG_FILE"
    fi
fi
# 部署重建文件后 waybar 需重读配置重建 inotify
pkill -SIGUSR2 waybar 2>/dev/null || true
echo "[$(date +%H:%M:%S)] SIGUSR2 sent to waybar" >> "$LOG_FILE"
