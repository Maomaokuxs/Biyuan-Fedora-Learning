#!/usr/bin/env python3
"""theme-gtk-sync.py — generate hud-breeze GTK colors from the central palette.

Reads ~/.cache/by-mgr/hellwal/global-palette.env (BG/FG/ACCENT),
writes the breeze @define-color variables to
    ~/.local/share/themes/hud-breeze/gtk-3.0/colors.css
    ~/.local/share/themes/hud-breeze/gtk-4.0/colors.css
and ensures gtk-theme-name=hud-breeze in settings.ini + gsettings.

Called by theme-sync.sh after the central palette is written.
Always exits 0 (never break the theme-sync chain); warnings go to stderr.
"""
import argparse
import os
import re
import subprocess
import sys

HOME = os.path.expanduser("~")
PALETTE = os.path.join(HOME, ".cache/by-mgr/hellwal/global-palette.env")
THEME_DIR = os.path.join(HOME, ".local/share/themes/hud-breeze")
THEME_NAME = "hud-breeze"

HEX_RE = re.compile(r"^#[0-9a-fA-F]{6}$")

# Variable order follows the breeze template (kept stable for diffing).
VAR_ORDER = [
    "borders_breeze",
    "content_view_bg_breeze",
    "error_color_backdrop_breeze",
    "error_color_breeze",
    "error_color_insensitive_backdrop_breeze",
    "error_color_insensitive_breeze",
    "insensitive_base_color_breeze",
    "insensitive_base_fg_color_breeze",
    "insensitive_bg_color_breeze",
    "insensitive_borders_breeze",
    "insensitive_fg_color_breeze",
    "insensitive_selected_bg_color_breeze",
    "insensitive_selected_fg_color_breeze",
    "insensitive_unfocused_bg_color_breeze",
    "insensitive_unfocused_fg_color_breeze",
    "insensitive_unfocused_selected_bg_color_breeze",
    "insensitive_unfocused_selected_fg_color_breeze",
    "link_color_breeze",
    "link_visited_color_breeze",
    "success_color_backdrop_breeze",
    "success_color_breeze",
    "success_color_insensitive_backdrop_breeze",
    "success_color_insensitive_breeze",
    "theme_base_color_breeze",
    "theme_bg_color_breeze",
    "theme_button_background_backdrop_breeze",
    "theme_button_background_backdrop_insensitive_breeze",
    "theme_button_background_insensitive_breeze",
    "theme_button_background_normal_breeze",
    "theme_button_decoration_focus_backdrop_breeze",
    "theme_button_decoration_focus_backdrop_insensitive_breeze",
    "theme_button_decoration_focus_breeze",
    "theme_button_decoration_focus_insensitive_breeze",
    "theme_button_decoration_hover_backdrop_breeze",
    "theme_button_decoration_hover_backdrop_insensitive_breeze",
    "theme_button_decoration_hover_breeze",
    "theme_button_decoration_hover_insensitive_breeze",
    "theme_button_foreground_active_backdrop_breeze",
    "theme_button_foreground_active_backdrop_insensitive_breeze",
    "theme_button_foreground_active_breeze",
    "theme_button_foreground_active_insensitive_breeze",
    "theme_button_foreground_backdrop_breeze",
    "theme_button_foreground_backdrop_insensitive_breeze",
    "theme_button_foreground_insensitive_breeze",
    "theme_button_foreground_normal_breeze",
    "theme_fg_color_breeze",
    "theme_header_background_backdrop_breeze",
    "theme_header_background_breeze",
    "theme_header_background_light_breeze",
    "theme_header_foreground_backdrop_breeze",
    "theme_header_foreground_breeze",
    "theme_header_foreground_insensitive_backdrop_breeze",
    "theme_header_foreground_insensitive_breeze",
    "theme_hovering_selected_bg_color_breeze",
    "theme_selected_bg_color_breeze",
    "theme_selected_fg_color_breeze",
    "theme_text_color_breeze",
    "theme_titlebar_background_backdrop_breeze",
    "theme_titlebar_background_breeze",
    "theme_titlebar_background_light_breeze",
    "theme_titlebar_foreground_backdrop_breeze",
    "theme_titlebar_foreground_breeze",
    "theme_titlebar_foreground_insensitive_backdrop_breeze",
    "theme_titlebar_foreground_insensitive_breeze",
    "theme_unfocused_base_color_breeze",
    "theme_unfocused_bg_color_breeze",
    "theme_unfocused_fg_color_breeze",
    "theme_unfocused_selected_bg_color_alt_breeze",
    "theme_unfocused_selected_bg_color_breeze",
    "theme_unfocused_selected_fg_color_breeze",
    "theme_unfocused_text_color_breeze",
    "theme_unfocused_view_bg_color_breeze",
    "theme_unfocused_view_text_color_breeze",
    "theme_view_active_decoration_color_breeze",
    "theme_view_hover_decoration_color_breeze",
    "tooltip_background_breeze",
    "tooltip_border_breeze",
    "tooltip_text_breeze",
    "unfocused_borders_breeze",
    "unfocused_insensitive_borders_breeze",
    "warning_color_backdrop_breeze",
    "warning_color_breeze",
    "warning_color_insensitive_backdrop_breeze",
    "warning_color_insensitive_breeze",
]


def rgb(h):
    h = h.lstrip("#")
    return tuple(int(h[i : i + 2], 16) for i in (0, 2, 4))


def hex3(r, g, b):
    return "#%02x%02x%02x" % (
        max(0, min(255, int(round(r)))),
        max(0, min(255, int(round(g)))),
        max(0, min(255, int(round(b)))),
    )


def mix(a, b, t):
    """Mix two hex colors; t=0 -> a, t=1 -> b."""
    ra, ga, ba = rgb(a)
    rb, gb, bb = rgb(b)
    return hex3(
        ra + (rb - ra) * t,
        ga + (gb - ga) * t,
        ba + (bb - ba) * t,
    )


def lum(h):
    def lin(c):
        c = c / 255.0
        return c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4

    r, g, b = (lin(c) for c in rgb(h))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def read_palette(path):
    pal = {}
    try:
        with open(path, encoding="utf-8") as f:
            for line in f:
                line = line.strip()
                if not line or "=" not in line or line.startswith("#"):
                    continue
                k, v = line.split("=", 1)
                pal[k.strip()] = v.strip().strip('"').strip("'")
    except OSError:
        return None
    if not all(HEX_RE.match(pal.get(k, "")) for k in ("BG", "FG", "ACCENT")):
        return None
    return pal


def build_vars(bg, fg, accent, dark):
    v = {}
    base = mix(bg, "#000000", 0.30) if dark else mix(bg, "#ffffff", 0.55)
    # Text on selection: whichever of fg/bg contrasts more with the accent.
    sel_fg = fg if contrast(accent, fg) >= contrast(accent, bg) else bg
    ins_fg = mix(bg, fg, 0.40)
    ins_base_fg = mix(bg, fg, 0.52)
    borders = mix(bg, fg, 0.22)
    btn_bg = mix(bg, fg, 0.07)

    if dark:
        error, warning, success = "#ff6e81", "#ff734a", "#64b046"
        link, link_v = "#6f9fe7", "#d97dcf"
    else:
        error, warning, success = "#e01b24", "#e66100", "#2ec27e"
        link, link_v = "#1c71d8", "#9141ac"

    v["borders_breeze"] = borders
    v["content_view_bg_breeze"] = base
    v["error_color_backdrop_breeze"] = error
    v["error_color_breeze"] = error
    v["error_color_insensitive_backdrop_breeze"] = mix(bg, error, 0.50)
    v["error_color_insensitive_breeze"] = mix(bg, error, 0.50)
    v["insensitive_base_color_breeze"] = base
    v["insensitive_base_fg_color_breeze"] = ins_base_fg
    v["insensitive_bg_color_breeze"] = bg
    v["insensitive_borders_breeze"] = mix(bg, fg, 0.13)
    v["insensitive_fg_color_breeze"] = ins_fg
    v["insensitive_selected_bg_color_breeze"] = mix(bg, accent, 0.30)
    v["insensitive_selected_fg_color_breeze"] = ins_fg
    v["insensitive_unfocused_bg_color_breeze"] = bg
    v["insensitive_unfocused_fg_color_breeze"] = ins_fg
    v["insensitive_unfocused_selected_bg_color_breeze"] = mix(bg, accent, 0.30)
    v["insensitive_unfocused_selected_fg_color_breeze"] = ins_fg
    v["link_color_breeze"] = link
    v["link_visited_color_breeze"] = link_v
    v["success_color_backdrop_breeze"] = success
    v["success_color_breeze"] = success
    v["success_color_insensitive_backdrop_breeze"] = mix(bg, success, 0.50)
    v["success_color_insensitive_breeze"] = mix(bg, success, 0.50)
    v["theme_base_color_breeze"] = base
    v["theme_bg_color_breeze"] = bg
    v["theme_button_background_backdrop_breeze"] = bg
    v["theme_button_background_backdrop_insensitive_breeze"] = bg
    v["theme_button_background_insensitive_breeze"] = bg
    v["theme_button_background_normal_breeze"] = btn_bg
    v["theme_button_decoration_focus_backdrop_breeze"] = accent
    v["theme_button_decoration_focus_backdrop_insensitive_breeze"] = mix(bg, accent, 0.50)
    v["theme_button_decoration_focus_breeze"] = accent
    v["theme_button_decoration_focus_insensitive_breeze"] = mix(bg, accent, 0.50)
    v["theme_button_decoration_hover_backdrop_breeze"] = accent
    v["theme_button_decoration_hover_backdrop_insensitive_breeze"] = mix(bg, accent, 0.50)
    v["theme_button_decoration_hover_breeze"] = accent
    v["theme_button_decoration_hover_insensitive_breeze"] = mix(bg, accent, 0.50)
    v["theme_button_foreground_active_backdrop_breeze"] = fg
    v["theme_button_foreground_active_backdrop_insensitive_breeze"] = ins_fg
    v["theme_button_foreground_active_breeze"] = sel_fg
    v["theme_button_foreground_active_insensitive_breeze"] = ins_fg
    v["theme_button_foreground_backdrop_breeze"] = fg
    v["theme_button_foreground_backdrop_insensitive_breeze"] = ins_fg
    v["theme_button_foreground_insensitive_breeze"] = ins_fg
    v["theme_button_foreground_normal_breeze"] = fg
    v["theme_fg_color_breeze"] = fg
    v["theme_header_background_backdrop_breeze"] = bg
    v["theme_header_background_breeze"] = bg
    v["theme_header_background_light_breeze"] = bg
    v["theme_header_foreground_backdrop_breeze"] = fg
    v["theme_header_foreground_breeze"] = fg
    v["theme_header_foreground_insensitive_backdrop_breeze"] = fg
    v["theme_header_foreground_insensitive_breeze"] = fg
    v["theme_hovering_selected_bg_color_breeze"] = mix(accent, fg, 0.30)
    v["theme_selected_bg_color_breeze"] = accent
    v["theme_selected_fg_color_breeze"] = sel_fg
    v["theme_text_color_breeze"] = fg
    v["theme_titlebar_background_backdrop_breeze"] = bg
    v["theme_titlebar_background_breeze"] = bg
    v["theme_titlebar_background_light_breeze"] = bg
    v["theme_titlebar_foreground_backdrop_breeze"] = fg
    v["theme_titlebar_foreground_breeze"] = fg
    v["theme_titlebar_foreground_insensitive_backdrop_breeze"] = fg
    v["theme_titlebar_foreground_insensitive_breeze"] = fg
    v["theme_unfocused_base_color_breeze"] = base
    v["theme_unfocused_bg_color_breeze"] = bg
    v["theme_unfocused_fg_color_breeze"] = fg
    v["theme_unfocused_selected_bg_color_alt_breeze"] = mix(bg, accent, 0.38)
    v["theme_unfocused_selected_bg_color_breeze"] = mix(bg, accent, 0.38)
    v["theme_unfocused_selected_fg_color_breeze"] = fg
    v["theme_unfocused_text_color_breeze"] = fg
    v["theme_unfocused_view_bg_color_breeze"] = bg
    v["theme_unfocused_view_text_color_breeze"] = ins_base_fg
    v["theme_view_active_decoration_color_breeze"] = mix(bg, accent, 0.45)
    v["theme_view_hover_decoration_color_breeze"] = mix(bg, accent, 0.45)
    v["tooltip_background_breeze"] = mix(bg, fg, 0.05)
    v["tooltip_border_breeze"] = mix(bg, fg, 0.32)
    v["tooltip_text_breeze"] = fg
    v["unfocused_borders_breeze"] = mix(bg, fg, 0.18)
    v["unfocused_insensitive_borders_breeze"] = mix(bg, fg, 0.13)
    v["warning_color_backdrop_breeze"] = warning
    v["warning_color_breeze"] = warning
    v["warning_color_insensitive_backdrop_breeze"] = mix(bg, warning, 0.50)
    v["warning_color_insensitive_breeze"] = mix(bg, warning, 0.50)

    missing = [k for k in VAR_ORDER if k not in v]
    if missing:
        raise AssertionError("missing breeze vars: %s" % ", ".join(missing))
    return v


def write_colors_css(path, vars):
    lines = ["/* generated by theme-gtk-sync.py — do not edit by hand */"]
    lines += ["@define-color %s %s;" % (k, vars[k]) for k in VAR_ORDER]
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(lines) + "\n")


def ensure_settings_ini(path):
    """Idempotently set gtk-theme-name=hud-breeze (line-based, keeps the rest)."""
    try:
        with open(path, encoding="utf-8") as f:
            lines = f.read().splitlines()
    except OSError:
        lines = ["[Settings]"]
    out, seen_settings, done = [], False, False
    for ln in lines:
        s = ln.strip()
        if s == "[Settings]":
            seen_settings = True
            out.append(ln)
            continue
        if s.startswith("gtk-theme-name"):
            out.append("gtk-theme-name=%s" % THEME_NAME)
            done = True
            continue
        out.append(ln)
    if not done:
        if seen_settings:
            idx = out.index("[Settings]")
            out.insert(idx + 1, "gtk-theme-name=%s" % THEME_NAME)
        else:
            out = ["[Settings]", "gtk-theme-name=%s" % THEME_NAME] + out
    with open(path, "w", encoding="utf-8") as f:
        f.write("\n".join(out) + "\n")


def set_gsettings_theme():
    try:
        subprocess.run(
            ["gsettings", "set", "org.gnome.desktop.interface", "gtk-theme", THEME_NAME],
            check=True,
            timeout=10,
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
    except Exception as e:
        print("theme-gtk-sync: gsettings skipped (%s)" % e, file=sys.stderr)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--dark", action="store_true")
    ap.add_argument("--light", action="store_true")
    args = ap.parse_args()

    pal = read_palette(PALETTE)
    if pal is None:
        print(
            "theme-gtk-sync: no valid palette at %s, keeping existing colors" % PALETTE,
            file=sys.stderr,
        )
        return 0
    bg, fg, accent = pal["BG"], pal["FG"], pal["ACCENT"]
    if args.dark:
        dark = True
    elif args.light:
        dark = False
    else:
        dark = lum(bg) < lum(fg)

    vars = build_vars(bg, fg, accent, dark)
    for sub in ("gtk-3.0", "gtk-4.0"):
        d = os.path.join(THEME_DIR, sub)
        os.makedirs(d, exist_ok=True)
        write_colors_css(os.path.join(d, "colors.css"), vars)
    for sub in ("gtk-3.0", "gtk-4.0"):
        ensure_settings_ini(os.path.join(HOME, ".config", sub, "settings.ini"))
    set_gsettings_theme()
    print(
        "theme-gtk-sync: hud-breeze colors written (%s) bg=%s fg=%s accent=%s"
        % ("dark" if dark else "light", bg, fg, accent)
    )
    return 0


if __name__ == "__main__":
    sys.exit(main())
