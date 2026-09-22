#!/bin/bash
# sync-waybar.sh — 从 Waybar 配色生成 fcitx5 皮肤
# 用法: bash sync-waybar.sh [--install]
#   默认在脚本所在目录生成 hud-paper / hud-paper-dark
#   --install 则额外安装到 ~/.local/share/fcitx5/themes/ 并重启 fcitx5
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
# 取色源：中央库优先（与全桌面同一数据源），color-waybar.css 仅作兜底
PALETTE="${PALETTE_FILE:-$HOME/.cache/by-mgr/hellwal/global-palette.env}"
CSS="${WAYBAR_CSS:-$HOME/.config/waybar/color-waybar.css}"

get_color() { # $1=name, 从 color-waybar.css 兜底读取
  grep -E "@define-color[[:space:]]+$1[[:space:]]+" "$CSS" | head -n1 | grep -oE '#[0-9a-fA-F]{6}'
}

if [[ -f "$PALETTE" ]]; then
  # shellcheck disable=SC1090
  source "$PALETTE" # 提供 BG FG ACCENT MUTED
  echo "中央库配色: bg=$BG fg=$FG accent=$ACCENT muted=$MUTED"
else
  echo "中央库缺失，回退到 $CSS"
fi
BG="${BG:-}"; FG="${FG:-}"; ACCENT="${ACCENT:-}"; MUTED="${MUTED:-}"
if [[ ! "$BG" =~ ^#[0-9a-fA-F]{6}$ || ! "$FG" =~ ^#[0-9a-fA-F]{6}$ ]]; then
  if [[ ! -f "$CSS" ]]; then echo "找不到配色来源" >&2; exit 1; fi
  BG="$(get_color bg)"; FG="$(get_color fg)"
fi
[[ "$ACCENT" =~ ^#[0-9a-fA-F]{6}$ ]] || ACCENT="$FG"
[[ "$MUTED" =~ ^#[0-9a-fA-F]{6}$ ]] || MUTED="$FG"
# 暗色底：中央库 COLOR0（真黑）；校验与派生在 python 里做（亮度对比，无硬编码）
DARK_RAW="${COLOR0:-}"
echo "Fcitx5 取色: bg=$BG fg=$FG accent=$ACCENT muted=$MUTED dark_raw=$DARK_RAW"

PALETTE_PATH="$PALETTE" python3 - "$BG" "$FG" "$DARK_RAW" "$ACCENT" "$SCRIPT_DIR" <<'PYEOF'
import sys, os, re
bg, fg, darkraw, accentraw, outdir = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4], sys.argv[5]

def lum(h):
    h = h.lstrip('#')
    lin = lambda c: c / 12.92 if c <= 0.03928 else ((c + 0.055) / 1.055) ** 2.4
    r, g, b = (lin(int(h[i:i + 2], 16) / 255) for i in (0, 2, 4))
    return 0.2126 * r + 0.7152 * g + 0.0722 * b

def valid(h):
    return isinstance(h, str) and re.fullmatch(r'#[0-9a-fA-F]{6}', h) is not None

# 暗色底：COLOR0 有效则用，否则取 BG/FG 中更暗的；暗色文字恒取更亮的。
# 白天 BG纸面/FG棕 → 底黑字纸面；夜间 BG深灰/FG白 → 底黑字白，永不撞色。
darkbg = darkraw if valid(darkraw) else (bg if lum(bg) < lum(fg) else fg)
lightcolor = bg if lum(bg) >= lum(fg) else fg

# 高亮块：壁纸主题 accent 色；字色在深浅两端里选对比度更高的，保证可读。
accent = accentraw if valid(accentraw) else fg
def contrast(a, b):
    la, lb = sorted((lum(a), lum(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)
hltext = darkbg if contrast(accent, darkbg) >= contrast(accent, lightcolor) else lightcolor

# 对比度兜底：任何字/底组合低于 4.5 即自动换字色（取色逻辑的最后一道闸）。
# 候选极端色来自中央库全量色板的最深/最浅（不够才用 BG/FG 两端），无硬编码。
_pool = []
_ppath = os.environ.get("PALETTE_PATH", "")
if _ppath and os.path.isfile(_ppath):
    for _ln in open(_ppath):
        _m = re.fullmatch(r'\s*[A-Za-z0-9_]+="?(#[0-9a-fA-F]{6})"?\s*', _ln.strip())
        if _m:
            _pool.append(_m.group(1))
_pool += [bg, fg, accent]
_pool = [c for c in _pool if valid(c)]
_darkest = min(_pool, key=lum)
_lightest = max(_pool, key=lum)
def guard(fg_, bg_, why):
    if contrast(fg_, bg_) >= 4.5:
        return fg_, bg_
    cand = max([_darkest, _lightest], key=lambda c: contrast(c, bg_))
    print(f"contrast guard [{why}]: {fg_} on {bg_} ({contrast(fg_, bg_):.2f}) -> {cand} on {bg_} ({contrast(cand, bg_):.2f})")
    return cand, bg_

# 整体缩放：默认 0.8，可用 FCITX_SCALE=1.0 覆盖（改这里或环境变量均可）
S = float(os.environ.get("FCITX_SCALE", "0.8"))
def px(v):
    return max(1, round(v * S))

VB = px(60)            # SVG 内禀尺寸：60*0.8=48
PR = px(18)            # 面板圆角半径：14
HR = px(14)            # 选中块圆角半径：11
PINSET, PSIZE = px(3), VB - px(3) * 2    # 面板外框：2,44
HINSET, HSIZE = px(4), VB - px(4) * 2    # 选中块外框：3,42
PM = PR                # 面板九宫格边距 = 圆角半径（48-28=20 中心可拉伸）
HM = HR                # 选中块九宫格边距（48-22=26 中心可拉伸）
HM_TB = px(10)         # 选中块纵向收紧（只压高度，宽度不动）
# 内容边距：隔离缝 = 内容边距 + 文字边距 − 选中块胀出，四边都按 2px 配平
# 横向：7 + 6 − 11 = 2；纵向：8 + 2 − 8 = 2
# 另需候选间距 (左6+右6=12) > 高亮横向胀出 (11)，否则高亮盖住下一个序号
CM_LR = px(9)
CM_TB = px(10)
SW = round(1.5 * S, 1) # 描边宽度：1.2

def rr(x, y, w, h, r):
    x1, y1 = x + w, y + h
    return (f"M {x+r},{y} H {x1-r} Q {x1},{y} {x1},{y+r} "
            f"V {y1-r} Q {x1},{y1} {x1-r},{y1} "
            f"H {x+r} Q {x},{y1} {x},{y1-r} "
            f"V {y+r} Q {x},{y} {x+r},{y} Z")

def panel_svg(panel, stroke):
    # 只用 <path>（fcitx5 对 <rect>/滤镜支持有 bug）；扁平无阴影。
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{VB}" height="{VB}" version="1.1" viewBox="0 0 {VB} {VB}" xmlns="http://www.w3.org/2000/svg">
  <path d="{rr(PINSET, PINSET, PSIZE, PSIZE, PR)}"
        fill="{panel}" fill-opacity="1"
        stroke="{stroke}" stroke-opacity="0.35" stroke-width="{SW}"/>
</svg>
'''

def highlight_svg(fill):
    return f'''<?xml version="1.0" encoding="UTF-8"?>
<svg width="{VB}" height="{VB}" version="1.1" viewBox="0 0 {VB} {VB}" xmlns="http://www.w3.org/2000/svg">
  <path d="{rr(HINSET, HINSET, HSIZE, HSIZE, HR)}"
        fill="{fill}" fill-opacity="1"/>
</svg>
'''

def theme_conf(name, desc, panel, text, hl_text, hl_bg):
    # 横排候选：FullWidthHighlight=False 让高亮只包住当前候选（HUD 色块感）
    # 高亮块模仿 waybar #clock 反色：hl_bg + hl_text
    tl, tr, tt, tb = px(8), px(8), px(3), px(3)
    ml, mr, mt, mb = px(6), px(6), px(5), px(5)
    mhm = px(8)
    cx, cy = px(5), px(4)
    return f'''[Metadata]
Name={name}
Version=1.0
Author=Biyuan (hud-paper)
Description={desc}
ScaleWithDPI=True

[InputPanel]
NormalColor={text}
HighlightCandidateColor={hl_text}
HighlightColor={hl_text}
HighlightBackgroundColor={hl_bg}
FullWidthHighlight=False
VerticalCandidateList=False
WheelForPaging=True
PageButtonAlignment=Last Candidate

[InputPanel/Background]
Image=panel.svg
Color={panel}
BorderColor={panel}00
BorderWidth=0

[InputPanel/Background/Margin]
Left={PM}
Right={PM}
Top={PM}
Bottom={PM}

[InputPanel/Highlight]
Image=highlight.svg
Color={hl_bg}
BorderColor={hl_bg}00
BorderWidth=0

[InputPanel/Highlight/Margin]
Left={HM}
Right={HM}
Top={HM_TB}
Bottom={HM_TB}

[InputPanel/ContentMargin]
Left={CM_LR}
Right={CM_LR}
Top={CM_TB}
Bottom={CM_TB}

[InputPanel/TextMargin]
Left={tl}
Right={tr}
Top={tt}
Bottom={tb}

[InputPanel/PrevPage]
Image=

[InputPanel/PrevPage/ClickMargin]
Left={cx}
Right={cx}
Top={cy}
Bottom={cy}

[InputPanel/NextPage]
Image=

[InputPanel/NextPage/ClickMargin]
Left={cx}
Right={cx}
Top={cy}
Bottom={cy}

[InputPanel/ShadowMargin]
Left=0
Right=0
Top=0
Bottom=0

[Menu]
NormalColor={text}
HighlightCandidateColor={hl_text}
Spacing=2

[Menu/Background]
Image=panel.svg
Color={panel}
BorderColor={panel}00
BorderWidth=0

[Menu/ContentMargin]
Left={px(14)}
Right={px(14)}
Top={px(14)}
Bottom={px(14)}

[Menu/TextMargin]
Left={ml}
Right={mr}
Top={mt}
Bottom={mb}

[Menu/Highlight]
Image=highlight.svg
Color={hl_bg}
BorderColor={hl_bg}00
BorderWidth=0

[Menu/Highlight/Margin]
Left={mhm}
Right={mhm}
Top={mhm}
Bottom={mhm}

[Menu/Separator]
Color={hl_bg}

[Menu/CheckBox]
Image=

[Menu/SubMenu]
Image=
'''

# 浅色：面板=waybar bg，文字=waybar fg，高亮=壁纸 accent 块 + 对比字
# guard 返回 (字, 底) 顺序
_ltext, _lpanel = guard(fg, bg, "light")
_lhl, _ = guard(hltext, accent, "light-hl")
light = ("hud-paper", "Hud Paper light — paper bg, accent selection",
         _lpanel, _ltext, _lhl, accent)
# 深色：底=黑（或更暗色），文字=更亮色，高亮=壁纸 accent 块 + 对比字
_dtext, _dpanel = guard(lightcolor, darkbg, "dark")
_dhl, _ = guard(hltext, accent, "dark-hl")
dark = ("hud-paper-dark", "Hud Paper dark — black panel, accent selection",
        _dpanel, _dtext, _dhl, accent)

for dirname, desc, panel, text, hl_text, hl_bg in (light, dark):
    d = os.path.join(outdir, dirname)
    os.makedirs(d, exist_ok=True)
    name = "Hud Paper" if dirname == "hud-paper" else "Hud Paper Dark"
    with open(os.path.join(d, "panel.svg"), "w") as f:
        f.write(panel_svg(panel, text))
    with open(os.path.join(d, "highlight.svg"), "w") as f:
        f.write(highlight_svg(hl_bg))
    with open(os.path.join(d, "theme.conf"), "w") as f:
        f.write(theme_conf(name, desc, panel, text, hl_text, hl_bg))
    print(f"生成 {d}/ (panel={panel} text={text} hl={hl_bg} scale={S})")
PYEOF

if [[ "${1:-}" == "--install" ]]; then
  DEST="${XDG_DATA_HOME:-$HOME/.local/share}/fcitx5/themes"
  mkdir -p "$DEST" "$HOME/.cache"
  # 无变化跳过：同昼夜模式下连切壁纸，生成的皮肤完全一致，
  # 重启输入法除了闪一下面板、偶发卡死丢空白窗之外毫无收益（2026-09 实测）。
  # 对两套主题目录整体哈希，与上次比对。
  HASH_FILE="$HOME/.cache/fcitx5-theme.hash"
  NEWHASH=$(find "$SCRIPT_DIR/hud-paper" "$SCRIPT_DIR/hud-paper-dark" -type f -exec md5sum {} + 2>/dev/null | md5sum | cut -d' ' -f1)
  if [ -n "$NEWHASH" ] && [ -f "$HASH_FILE" ] && [ "$(cat "$HASH_FILE" 2>/dev/null)" = "$NEWHASH" ]; then
    echo "   Fcitx5 皮肤无变化，跳过安装与重启"
    exit 0
  fi
  echo "$NEWHASH" > "$HASH_FILE"
  # 原子换装：fcitx5 的 -r/portal延迟重载随时可能读文件，
  # 若直接 cp -r 覆盖，必撞上新旧混版（白字+白底即这么来的）。
  # 先 stage 再整目录 rename，读到的永远是完整的一代。
  install_theme() { # $1=主题目录名
    local name="$1" stage bak
    stage="$(mktemp -d "$HOME/.cache/fcitx5-stage-XXXXXX")"
    cp -r "$SCRIPT_DIR/$name/." "$stage/"
    if [[ -d "$DEST/$name" ]]; then
      bak="$DEST/$name.bak"
      rm -rf "$bak"
      mv "$DEST/$name" "$bak" && mv "$stage" "$DEST/$name"
      rm -rf "$bak" "$stage"
    else
      mv "$stage" "$DEST/$name"
    fi
  }
  install_theme hud-paper
  install_theme hud-paper-dark
  echo "已安装到 $DEST/hud-paper{,-dark}"
  # 彻底重载：优先 fcitx5-remote -r 原地重载（不断进程，无空白窗、无输入中断）；
  # 只有 remote 不通才冷启动。注意：绝不用裸 `fcitx5 -r`（会卡死在半当中，
  # 旧守护已卸载、新的没起来，还丢空白面板窗——2026-09 实测）。
  # 健康定义：fcitx5-remote --check 退出 0（文档：没跑返回 1）。
  if fcitx5-remote -r >/dev/null 2>&1; then
    echo "   fcitx5 已原地重载"
  else
    echo "   ( remote 重载失败，走冷启动)"
  fi
  ok=false
  for i in 1 2 3 4 5; do
    sleep 3
    if fcitx5-remote --check >/dev/null 2>&1; then ok=true; break; fi
    # 只杀残留 waiter，不碰健康守护：remote 不通时在场 fcitx5 进程即视为残留
    pkill -x fcitx5 2>/dev/null
    sleep 1
    setsid fcitx5 -d >/dev/null 2>&1 </dev/null &
  done
  # 健康守卫：5 轮约 15s 还不通（rime 首载慢也覆盖了）才算真死，大声报错
  if $ok; then
    echo "   fcitx5 健康"
  else
    echo "   ( fcitx5 拉起失败！)"
    notify-send -u critical "输入法异常" "fcitx5 多次拉起失败，请手动检查（fcitx5 -d）" 2>/dev/null &
  fi
fi
