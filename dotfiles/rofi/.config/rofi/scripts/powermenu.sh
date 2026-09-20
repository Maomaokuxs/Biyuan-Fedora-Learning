#!/bin/bash

# ==========================================
# Rofi 极简电源菜单 (Niri / Fedora 专属)
# ==========================================

# 1. 获取系统运行时间，作为左侧面板的展示信息
UPTIME=$(uptime -p | sed -e 's/up //g')
HOST_INFO=" $USER |  $UPTIME"

# 2. 定义 6 个控制按钮的图标与文字 (使用 Nerd Fonts)
LOCK=" Lock"
SUSPEND="󰤄 Sleep"
HIBERNATE="󰒲 Hibern"
LOGOUT="󰍃 Logout"
REBOOT="󰜉 Reboot"
SHUTDOWN="󰐥 Poweroff"

# 3. 呼出 Rofi 面板
# 使用 -selected-row 0 默认高亮锁屏键，防止误触关机
SELECTED=$(echo -e "$LOCK\n$SUSPEND\n$HIBERNATE\n$LOGOUT\n$REBOOT\n$SHUTDOWN" | \
           rofi -dmenu -i -p "$HOST_INFO" \
           -theme ~/.config/rofi/themes/powermenu.rasi \
           -selected-row 0)

# 4. 执行对应操作

case "$SELECTED" in
    "$LOCK")
        loginctl lock-session ;;
    "$SUSPEND")
        # 推荐：先锁定，稍微等待让 Layer Shell 渲染，再休眠
        loginctl lock-session && sleep 0.5 && systemctl suspend ;;
     "$HIBERNATE")
        # 1. 向系统发送标准锁定信号，hypridle 会收到并立刻调起 hyprlock
        loginctl lock-session
        # 2. 强制等待 1 秒，确保锁屏界面已经在显卡中渲染完成
        sleep 1
        # 3. 无休眠配置的机器直接 hibernate 会失败且无兜底，走 sleep-safe.sh：
        # 有物理 swap + resume= 才休眠，否则降级挂起，再不行保底熄屏
        if swapon --show --noheadings 2>/dev/null | grep -v "zram" | grep -q . \
            && grep -q "resume=" /proc/cmdline 2>/dev/null; then
            systemctl hibernate
        else
            notify-send -i dialog-warning "休眠不可用" "未检测到物理 swap / resume= 参数，已降级挂起" -t 4000 2>/dev/null &
            bash ~/.config/hypr/scripts/sleep-safe.sh
        fi
        ;;
    "$LOGOUT")
        # niri 登出：优先 niri quit，失败回退 loginctl
        if pgrep -x niri >/dev/null 2>&1; then
            niri msg action quit
        else
            loginctl terminate-session "${XDG_SESSION_ID:-$(loginctl show-user "$USER" -p Display --value 2>/dev/null)}"
        fi
        ;;
     "$REBOOT")
        systemctl reboot ;;
    "$SHUTDOWN")
        systemctl poweroff ;;
esac
