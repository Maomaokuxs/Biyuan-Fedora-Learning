#!/bin/bash
# lib/utils.sh — 公共工具（无仓库扫描，已按需求删除 HOME 深度扫描）
BLUE='\033[0;34m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; RED='\033[0;31m'; CYAN='\033[0;36m'; PURPLE='\033[0;35m'; NC='\033[0m'; BOLD='\033[1m'

SCRIPT_PATH=$(readlink -f "${BASH_SOURCE[0]}")
LIB_DIR=$(dirname "$SCRIPT_PATH")
REPO_DIR=$(dirname "$(dirname "$LIB_DIR")")
if [ ! -d "$REPO_DIR/dotfiles" ]; then
    CUR="$LIB_DIR"
    for _ in 1 2 3 4 5; do
        CUR=$(dirname "$CUR")
        [ -d "$CUR/dotfiles" ] && REPO_DIR="$CUR" && break
    done
fi
# 本地无仓 fallback：~/.local/share/by-mgr
if [ ! -d "$REPO_DIR/dotfiles" ] && [ -d "$HOME/.local/share/by-mgr/dotfiles" ]; then
    REPO_DIR="$HOME/.local/share/by-mgr"
fi
# 临时日志目录（按你建议，每次测试后读取）
LOG_DIR="${BY_MGR_LOG_DIR:-/tmp/by-mgr}"
mkdir -p "$LOG_DIR" 2>/dev/null || true
DOTFILES_DIR="$REPO_DIR/dotfiles"
BACKUP_ROOT="$HOME/.config/by-mgr/backup"
USER_CONFIG_DIR="$HOME/.config/by-mgr"

if [ ! -d "$DOTFILES_DIR" ]; then
    echo -e "${RED}错误: 无法定位 dotfiles 目录，推算仓库根为: $REPO_DIR${NC}" >&2
    exit 1
fi

_sudo_guard() {
    local desc="${1:-此操作}"
    if ! sudo -v 2>/dev/null; then
        echo -e "${YELLOW}>> 操作已取消（需要 sudo 权限）。${NC}" >&2
        return 1
    fi
    return 0
}
get_target_path() {
    local mod="$1"
    local base_path="$HOME/.config/$mod"
    if [ ! -d "$base_path" ] && [ -f "${base_path}.toml" ]; then echo "${base_path}.toml"
    elif [ ! -d "$base_path" ] && [ -f "${base_path}.conf" ]; then echo "${base_path}.conf"
    elif [ "$mod" = "bash" ]; then echo "$HOME/.bashrc"
    else echo "$base_path"; fi
}
clean_target() {
    local target="$1"
    [ -L "$target" ] && rm -f "$target" || true
    [ -d "$target" ] && [ ! -L "$target" ] && rm -rf "$target" || true
    [ -f "$target" ] && [ ! -L "$target" ] && rm -f "$target" || true
    return 0
}
enable_repo_compat() {
    if command -v dnf5 &>/dev/null || dnf --version 2>/dev/null | grep -q "dnf5"; then
        sudo dnf config-manager setopt "$1.enabled=1" 2>/dev/null
    else
        sudo dnf config-manager --set-enabled "$1" 2>/dev/null
    fi
}
disable_repo_compat() {
    if command -v dnf5 &>/dev/null || dnf --version 2>/dev/null | grep -q "dnf5"; then
        sudo dnf config-manager setopt "$1.enabled=0" 2>/dev/null
    else
        sudo dnf config-manager --set-disabled "$1" 2>/dev/null
    fi
}
list_snapshots() {
    ls -d "$BACKUP_ROOT"/* 2>/dev/null | grep -E '[0-9]{8}_[0-9]+' | sort
}
