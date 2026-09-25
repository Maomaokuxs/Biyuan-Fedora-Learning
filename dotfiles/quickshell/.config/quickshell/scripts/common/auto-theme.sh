#!/bin/bash
# auto-theme.sh — Waybar 昼夜自动切换
# 逻辑：06:00-18:00 日间，其余夜间；每 interval 检查一次，自动切换 GTK+KDE 主题
# Waybar: return-type json, on-click 手动切换

DAY_START=6
DAY_END=18
HOUR=$(date +%H)
HOUR=${HOUR#0}

if [ "$HOUR" -ge "$DAY_START" ] && [ "$HOUR" -lt "$DAY_END" ]; then
    TARGET="day"
else
    TARGET="night"
fi

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

apply_day() {
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-light' 2>/dev/null
    apply_gtk_theme day
    if plasma-apply-colorscheme -l 2>/dev/null | grep -q "MaterialYouLight"; then
        plasma-apply-colorscheme MaterialYouLight 2>/dev/null &
    else
        plasma-apply-colorscheme BreezeLight 2>/dev/null &
    fi
}

apply_night() {
    gsettings set org.gnome.desktop.interface color-scheme 'prefer-dark' 2>/dev/null
    apply_gtk_theme night
    if plasma-apply-colorscheme -l 2>/dev/null | grep -q "MaterialYouDark"; then
        plasma-apply-colorscheme MaterialYouDark 2>/dev/null &
    else
        plasma-apply-colorscheme BreezeDark 2>/dev/null &
    fi
}

CURRENT=$(gsettings get org.gnome.desktop.interface color-scheme 2>/dev/null)

# 手动覆盖保护：若 2 小时内手动切换过，跳过自动纠正，避免覆盖用户意图（Chrome/QQ 等原生应用会因此“改不回去”）
MANUAL_FLAG="/tmp/theme_manual_override"
if [ -f "$MANUAL_FLAG" ]; then
    age=$(( $(date +%s) - $(stat -c %Y "$MANUAL_FLAG" 2>/dev/null || echo 0) ))
    if [ "$age" -lt 7200 ]; then
        # 仍输出当前状态，不自动切换
        if [ "$CURRENT" = "'prefer-dark'" ]; then
            echo '{"text":"󰖔","tooltip":"夜间模式 (点击切换, 手动覆盖中)","class":"night"}'
        else
            echo '{"text":"󰖙","tooltip":"日间模式 (点击切换, 手动覆盖中)","class":"day"}'
        fi
        exit 0
    fi
fi

# 自动纠正：仅当目标与当前不一致时切换，并重跑取色联动配色
if [ "$TARGET" = "day" ] && [ "$CURRENT" = "'prefer-dark'" ]; then
    apply_day
    FCITX_FULL_RELOAD=1 bash ~/.config/niri/scripts/theme-sync.sh &>/dev/null &
    CURRENT="'default'"
elif [ "$TARGET" = "night" ] && [ "$CURRENT" != "'prefer-dark'" ]; then
    apply_night
    FCITX_FULL_RELOAD=1 bash ~/.config/niri/scripts/theme-sync.sh &>/dev/null &
    CURRENT="'prefer-dark'"
fi

# Waybar 输出
if [ "$CURRENT" = "'prefer-dark'" ]; then
    echo '{"text":"󰖔","tooltip":"夜间模式 (点击切换)","class":"night"}'
else
    echo '{"text":"󰖙","tooltip":"日间模式 (点击切换)","class":"day"}'
fi
