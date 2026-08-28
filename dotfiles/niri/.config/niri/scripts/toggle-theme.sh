#!/bin/bash
# toggle-theme.sh — 手动昼夜切换（与 auto-theme.sh 保持一致）

CURRENT=$(gsettings get org.gnome.desktop.interface color-scheme)

if [ "$CURRENT" == "'prefer-dark'" ]; then
    # 切换到日间 — 通用：仅切 color-scheme 与 prefer-dark，不绑定特定主题名
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=false/' ~/.config/gtk-3.0/settings.ini 2>/dev/null
    sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=false/' ~/.config/gtk-4.0/settings.ini 2>/dev/null
    # KDE：优先 MaterialYouLight，缺省回退 BreezeLight（系统自带）
    if plasma-apply-colorscheme -l 2>/dev/null | grep -q "MaterialYouLight"; then
        plasma-apply-colorscheme MaterialYouLight 2>/dev/null &
    else
        plasma-apply-colorscheme BreezeLight 2>/dev/null &
    fi
else
    # 切换到夜间
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=true/' ~/.config/gtk-3.0/settings.ini 2>/dev/null
    sed -i 's/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=true/' ~/.config/gtk-4.0/settings.ini 2>/dev/null
    if plasma-apply-colorscheme -l 2>/dev/null | grep -q "MaterialYouDark"; then
        plasma-apply-colorscheme MaterialYouDark 2>/dev/null &
    else
        plasma-apply-colorscheme BreezeDark 2>/dev/null &
    fi
fi
# 标记手动覆盖，2 小时内 auto-theme 不自动改回
touch /tmp/theme_manual_override
# 刷新 waybar 主题模块
pkill -RTMIN+12 waybar 2>/dev/null
