#!/usr/bin/env python3
"""check-colors.py — 配色一致性门禁（只检查，不改任何颜色设计）。
规则（违反即 exit 1）：
1. 禁止命令式改色：形如 root.normalBg = / root.normalFg = 的 JS 赋值会
   永久打断 QML 绑定，换壁纸后该模块再也跟不上（inhibit/fcitx 事故根因）。
   配色只允许走属性绑定。
2. 禁止散落的 hex 色值：颜色只能来自 Theme.qml（基础+派生）与 Icons.qml
  （图标是字形不算颜色不管），外加 transparent 结构位与电平火花块。
3. 每个 pill 实例必须显式声明配色来源（baseBg+baseFg 或 normalBg+normalFg），
   不许依赖 Pill.qml 里的 fallback 默认值（旧浅色，换壁纸就露馅）。
用法: python3 scripts/check-colors.py [--strict]
"""
import pathlib
import re
import sys

Q = pathlib.Path('/home/biyuan/Documents/quickshell')
fails = []


def check_no_imperative():
    for p in sorted((Q / 'bar').glob('*.qml')) + sorted((Q / 'components').glob('*.qml')):
        t = p.read_text(encoding='utf-8')
        for m in re.finditer(r'root\.(normalBg|normalFg)\s*=', t):
            fails.append(f'{p.name}: 命令式改色 {m.group(0)}（会打断绑定）')


def check_no_hex():
    allowed_files = {'Theme.qml', 'Icons.qml'}
    for p in sorted((Q / 'bar').glob('*.qml')) + sorted((Q / 'components').glob('*.qml')) \
            + sorted((Q / 'dock').glob('*.qml')) + [Q / 'shell.qml']:
        if p.name in allowed_files:
            continue
        for i, line in enumerate(p.read_text(encoding='utf-8').splitlines(), 1):
            code = line.split('//')[0]
            for m in re.finditer(r'"#[0-9a-fA-F]{3,8}"', code):
                if 'FALLBACK' in line:
                    continue
                fails.append(f'{p.name}:{i}: 散落 hex {m.group(0)}（请走 Theme/Icons，或打 FALLBACK 标并确保有实例覆盖）')


def check_explicit_source():
    text = (Q / 'bar' / 'Bar.qml').read_text(encoding='utf-8')
    blocks = re.findall(r'Comp\.(?:ScriptPill|Pill|AudioPill|BatteryPill|BluetoothPill|MusicInfo|MprisButton)\s*\{(.*?)\n    \}', text, re.S)
    for b in blocks:
        has_bg = ('baseBg:' in b) or ('normalBg:' in b)
        has_fg = ('baseFg:' in b) or ('normalFg:' in b)
        if not (has_bg and has_fg):
            first = b.strip().splitlines()[0][:70] if b.strip() else '?'
            fails.append(f'Bar.qml: pill 缺显式配色来源: {first}')


check_no_imperative()
check_no_hex()
check_explicit_source()

if fails:
    print('配色门禁未通过（%d 项，设计本身不动，只修 plumbing）：' % len(fails))
    for f in fails:
        print(' -', f)
    sys.exit(1)
print('配色门禁通过：无命令式改色、无散落 hex、全实例显式绑定。')
