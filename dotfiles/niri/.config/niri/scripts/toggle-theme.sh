#!/bin/bash
# toggle-theme.sh — 手动昼夜切换（与 auto-theme.sh 保持一致）

# 先标记手动覆盖（放最前，避免与 auto-theme 每秒轮询竞态），2 小时内不被自动改回
touch /tmp/theme_manual_override
CURRENT=$(gsettings get org.gnome.desktop.interface color-scheme)

theme_exists() {
    [ -d "$HOME/.themes/$1" ] || [ -d "$HOME/.local/share/themes/$1" ] || [ -d "/usr/share/themes/$1" ]
}

theme_has_dark_css() {
    local n="$1" root
    for root in "$HOME/.themes" "$HOME/.local/share/themes" "/usr/share/themes"; do
        [ -f "$root/$n/gtk-3.0/gtk-dark.css" ] && return 0
        [ -f "$root/$n/gtk-4.0/gtk-dark.css" ] && return 0
    done
    return 1
}

resolve_light_theme() {
    local cur base t
    cur=$(gsettings get org.gnome.desktop.interface gtk-theme 2>/dev/null)
    cur=${cur#\'}; cur=${cur%\'}
    [ -z "$cur" ] && cur="Adwaita"
    case "$cur" in
        *-Dark|*-dark)
            base="${cur%-Dark}"; base="${base%-dark}"
            for t in "$base-Light" "$base-light" "$base"; do
                theme_exists "$t" && { printf '%s' "$t"; return; }
            done
            ;;
    esac
    printf '%s' "$cur"
}

resolve_dark_theme() {
    local light="$1" base t
    case "$light" in
        *-Light|*-light)
            base="${light%-Light}"; base="${base%-light}"
            for t in "$base-Dark" "$base-dark"; do
                theme_exists "$t" && { printf '%s' "$t"; return; }
            done
            ;;
        *)
            for t in "$light-Dark" "$light-dark"; do
                theme_exists "$t" && { printf '%s' "$t"; return; }
            done
            ;;
    esac
    printf '%s' "$light"
}

apply_gtk_theme() {
    local mode="$1" prefer target light
    if [ "$mode" = "day" ]; then prefer=false; else prefer=true; fi
    light=$(resolve_light_theme)
    target="$light"
    if [ "$mode" = "night" ] && ! theme_has_dark_css "$light"; then
        target=$(resolve_dark_theme "$light")
    fi
    [ -n "$target" ] && gsettings set org.gnome.desktop.interface gtk-theme "$target" 2>/dev/null
    for f in "$HOME"/.config/gtk-2.0/settings.ini "$HOME"/.config/gtk-3.0/settings.ini "$HOME"/.config/gtk-4.0/settings.ini; do
        [ -f "$f" ] || continue
        [ -n "$target" ] && sed -i "s/^gtk-theme-name=.*/gtk-theme-name=$target/" "$f"
        sed -i "s/^gtk-application-prefer-dark-theme=.*/gtk-application-prefer-dark-theme=$prefer/" "$f"
    done
}

if [ "$CURRENT" == "'prefer-dark'" ]; then
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light'
    apply_gtk_theme day
    if plasma-apply-colorscheme -l 2>/dev/null | grep -q "MaterialYouLight"; then
        plasma-apply-colorscheme MaterialYouLight 2>/dev/null
    else
        plasma-apply-colorscheme BreezeLight 2>/dev/null
    fi
else
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark'
    apply_gtk_theme night
    if plasma-apply-colorscheme -l 2>/dev/null | grep -q "MaterialYouDark"; then
        plasma-apply-colorscheme MaterialYouDark 2>/dev/null
    else
        plasma-apply-colorscheme BreezeDark 2>/dev/null
    fi
fi
# 昼夜联动：重跑取色，按新昼夜模式再生配色
FCITX_FULL_RELOAD=1 bash ~/.config/niri/scripts/theme-sync.sh &>/dev/null
# 刷新 waybar 主题模块
pkill -RTMIN+12 waybar 2>/dev/null || true
