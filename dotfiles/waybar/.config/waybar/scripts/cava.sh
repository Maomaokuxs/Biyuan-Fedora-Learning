#!/bin/bash

# 如果已经有脚本在运行，先杀掉它，防止多重频谱叠加
pkill -f "cava -p ~/.cache/by-mgr/waybar_cava.conf" 2>/dev/null

# ==========================================
# Cava 智能音频后端选择器 (PipeWire / Pulse)
# ==========================================

# 1. 检查 Cava 二进制文件是否原生编译了 PipeWire 支持
CAVA_BIN=$(command -v cava)
if ldd "$CAVA_BIN" 2>/dev/null | grep -q "libpipewire"; then
    CAVA_SUPPORT_PW=true
else
    CAVA_SUPPORT_PW=false
fi

# 2. 检查当前系统是否正在运行 pipewire 进程
if pgrep -x "pipewire" > /dev/null; then
    SYS_RUNNING_PW=true
else
    SYS_RUNNING_PW=false
fi

# 3. 核心决策树：自主选择最优后端
# 只有当 Cava 支持且系统也在跑 PipeWire 时，才使用原生 PipeWire
if [ "$CAVA_SUPPORT_PW" = true ] && [ "$SYS_RUNNING_PW" = true ]; then
    AUDIO_METHOD="pipewire"
else
    # 否则，一律降级使用 PulseAudio (或其兼容层) 最稳妥
    AUDIO_METHOD="pulse"
fi

# ==========================================
# 生成动态配置文件
# ==========================================
config_file="~/.cache/by-mgr/waybar_cava.conf"

cat <<EOF > "$config_file"
[general]
bars = 10

[input]
# 脚本自主决定的音频后端
method = $AUDIO_METHOD
source = auto

[output]
method = raw
raw_target = /dev/stdout
data_format = ascii
ascii_max_range = 7
EOF

# ==========================================
# 运行 Cava 并通过 sed 渲染频谱动画
# ==========================================
# (如果你发现 Waybar 里没声音，可以尝试取消注释下面这行强制 pw-pulse 牵引)
# pw-pulse cava -p "$config_file" | sed -u 's/\;//g;s/0/ /g;s/1/▂/g;s/2/▃/g;s/3/▄/g;s/4/▅/g;s/5/▆/g;s/6/▇/g;s/7/█/g'

cava -p "$config_file" | sed -u 's/\;//g;s/0/ /g;s/1/▂/g;s/2/▃/g;s/3/▄/g;s/4/▅/g;s/5/▆/g;s/6/▇/g;s/7/█/g'

# 这是一个管道操作。当你只杀掉 waybar 时，cava 可能会因为管道破裂（Broken Pipe）退出，但 sed 有时会卡在后台。连带 pkill sed（或者更精确的 pkill -f sed.*cava）能保证清理得干干净净。

cava -p "$config_file" | sed -u 's/\;//g;...'
