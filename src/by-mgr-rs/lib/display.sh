#!/bin/bash
# display.sh - 当前终端直接打开 niri 输出配置（ui 已 LeaveAlternateScreen）
FILE="$HOME/Documents/github/Biyuan-Fedora-Learning/dotfiles/niri/.config/niri/niri-outputs.kdl"
mkdir -p "$(dirname "$FILE")"
[ -f "$FILE" ] || cat > "$FILE" <<'KDL'
// 由 by-mgr display 管理，niri 自动引入
output "eDP-1" {
    mode "1920x1080@60"
}
KDL
EDITOR_CMD="${EDITOR:-nano}"
case "$EDITOR_CMD" in
    *nvim*|*nano*|*vim*|*emacs*|*vi*|*micro*)
        # 终端编辑器：当前终端全屏打开，退出后返回 ratatui
        "$EDITOR_CMD" "$FILE"
        ;;
    *)
        # GUI 编辑器：后台打开，直接返回
        "$EDITOR_CMD" "$FILE" 2>/dev/null &
        ;;
esac
