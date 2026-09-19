#!/bin/bash
# lib/deploy.sh — 部署配置
# 用法: deploy.sh [stow|local] (默认 stow，兼容 physical)
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

mode="${1:-stow}"
# 兼容 physical 旧称
if [ "$mode" = "physical" ] || [ "$mode" = "phys" ]; then mode="local"; fi
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
echo "[$(date +%H:%M:%S)] deploy START mode=$mode" > "$LOG_FILE"
if [ -z "${BY_MGR_QUIET:-}" ]; then
    echo -e "\n${BLUE}>> 正在部署配置 (${mode})...${NC}" | tee -a "$LOG_FILE"
else
    echo ">> 正在部署配置 ($mode)..." >> "$LOG_FILE"
fi
# 清理历史遗留的 waybar 桥接软链（防 stow absolute symlink 冲突）
[ -d "$DOTFILES_DIR/waybar/.cache" ] && rm -rf "$DOTFILES_DIR/waybar/.cache" 2>/dev/null || true
for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
    [[ "$module" == "bash" ]] && continue
    [[ "$module" == "by-mgr" ]] && continue  # by-mgr 独立目录，不 stow
    target=$(get_target_path "$module")
    if [ "$mode" = "stow" ]; then
        # 兼容处理：starship 的 starship_base.toml 为模板，physical 残留的实体会阻塞 stow
        if [ "$module" = "starship" ] && [ -f "$HOME/.config/starship_base.toml" ] && [ ! -L "$HOME/.config/starship_base.toml" ]; then
            rm -f "$HOME/.config/starship_base.toml" 2>/dev/null || true
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  ${YELLOW}[兼容] 已清理残留 starship_base.toml${NC}" | tee -a "$LOG_FILE"
            else
                echo "  [兼容] 已清理残留 starship_base.toml" >> "$LOG_FILE"
            fi
        fi
        if [ "$module" = "plasma-apply-colorscheme" ] && [ -f "$HOME/.local/bin/plasma-apply-colorscheme" ] && [ ! -L "$HOME/.local/bin/plasma-apply-colorscheme" ]; then
            rm -f "$HOME/.local/bin/plasma-apply-colorscheme" 2>/dev/null || true
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  ${YELLOW}[兼容] 已清理残留 plasma-apply-colorscheme${NC}" | tee -a "$LOG_FILE"
            else
                echo "  [兼容] 已清理残留 plasma-apply-colorscheme" >> "$LOG_FILE"
            fi
        fi
        # 先尝试回收旧链接，失败不隐藏错误（便于排查）
        (cd "$DOTFILES_DIR" && stow -D -t "$HOME" "$module" 2>&1 | tee -a "$LOG_FILE" || true)
        # stow 前彻底清理本地实文件残留（fastfetch 等单文件冲突）
        if [ -e "$target" ] || [ -L "$target" ]; then
            rm -rf "$target" 2>/dev/null || true
        fi
        clean_target "$target"
        if (cd "$DOTFILES_DIR" && stow -v -t "$HOME" "$module" 2>&1 | tee -a "$LOG_FILE"; test ${PIPESTATUS[0]} -eq 0); then
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "  [🔗 Linked] $module" | tee -a "$LOG_FILE"
            else
                echo "  [🔗 Linked] $module" >> "$LOG_FILE"
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
        # 本地部署：遇同名文件先询问是否快照
        if [ -e "$target" ] || [ -L "$target" ]; then
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo -e "${YELLOW}⚠️  检测到已存在 $target${NC}" | tee -a "$LOG_FILE"
                echo -e "${YELLOW}   是否先创建快照以防误删？ [y/N]${NC}" | tee -a "$LOG_FILE"
                read -p "   输入 y 创建快照，直接回车跳过: " ans < /dev/tty || true
                if [[ "$ans" == "y" || "$ans" == "Y" ]]; then
                    echo -e "${BLUE}>> 正在创建快照...${NC}" | tee -a "$LOG_FILE"
                    bash "$SCRIPT_DIR/snapshot.sh" 2>&1 | tee -a "$LOG_FILE" || true
                    echo -e "${GREEN}✅ 快照已创建，继续本地部署...${NC}" | tee -a "$LOG_FILE"
                else
                    echo -e "${CYAN}>> 跳过快照，直接覆盖...${NC}" | tee -a "$LOG_FILE"
                fi
            else
                echo "[本地部署] 检测到已存在 $target，将直接覆盖 (quiet 模式)" >> "$LOG_FILE"
            fi
        fi
        (cd "$DOTFILES_DIR" && stow -D -t "$HOME" "$module" 2>/dev/null || true)
        clean_target "$target"
        if [ -d "$DOTFILES_DIR/$module/.config" ]; then
            cp -a "$DOTFILES_DIR/$module/.config/." "$HOME/.config/" 2>/dev/null || true
        elif [ -f "$DOTFILES_DIR/$module/.config/$module.toml" ]; then
            cp -a "$DOTFILES_DIR/$module/.config/$module.toml" "$HOME/.config/" 2>/dev/null || true
        else
            cp -a "$DOTFILES_DIR/$module/." "$HOME/" 2>/dev/null || true
        fi
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo -e "  [📁 Physical] $module" | tee -a "$LOG_FILE"
        else
            echo "  [📁 Physical] $module" >> "$LOG_FILE"
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
    bash "$HOME/.config/niri/scripts/theme-sync.sh" "$WALLPAPER" || true
fi
if [ "$failed" -gt 0 ]; then
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${RED}❌ 部署完成，${failed} 个模块失败 (详见 $LOG_FILE)${NC}" | tee -a "$LOG_FILE"
    else
        echo "❌ 部署完成，${failed} 个模块失败" | tee -a "$LOG_FILE"
    fi
    exit 1
else
    echo "✅ 部署完成 ($mode)" | tee -a "$LOG_FILE"
fi
# 部署重建文件后 waybar 需重读配置重建 inotify
pkill -SIGUSR2 waybar 2>/dev/null || true
echo "[$(date +%H:%M:%S)] SIGUSR2 sent to waybar" >> "$LOG_FILE"
