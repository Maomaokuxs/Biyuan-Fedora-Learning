#!/bin/bash

# --- 路径与文件配置 ---
SAVE_DIR="$HOME/Videos/Recordings"
mkdir -p "$SAVE_DIR"
STATUS_FILE="/tmp/recording_status"
LOG_FILE="/tmp/gsr_error.log"

# --- 函数：发送 Waybar 刷新信号 ---
refresh_waybar() {
    # 对应 Waybar 配置中的 "signal": 9
    pkill -RTMIN+9 waybar
}

# --- 逻辑：检查并停止录制 ---
if pgrep -f "gpu-screen-recorder" > /dev/null; then
    pkill -INT -f "gpu-screen-recorder"
    
    # 等待进程完全退出以确保文件写入
    while pgrep -f "gpu-screen-recorder" > /dev/null; do sleep 0.5; done
    
    # 🔴 核心改进：清理状态文件并立刻刷新一次 Waybar，清除残留计时
    rm -f "$STATUS_FILE"
    refresh_waybar
    
    # 发送带 Action 的通知 (点击可打开 Dolphin)
    ACTION=$(notify-send "󰑊 录屏已保存" "文件存放在: <b>$SAVE_DIR</b>\n点击此处打开目录" \
        -i folder-videos-symbolic \
        -a "Recorder" \
        --action="open_folder=打开文件夹")

    # 监听 Mako 的反馈动作
    if [ "$ACTION" == "open_folder" ]; then
        dolphin "$SAVE_DIR" &
    fi
    exit 0
fi

# --- Rofi 菜单配置 ---
OPTIONS="󰕧  MP4 全屏 (H.264)\n󰕧  MKV 全屏 (无损)\n󰕧  GIF 全屏\n󰹑  MP4 区域\n󰹑  MKV 区域\n󰹑  GIF 区域"

CHOSEN=$(echo -e "$OPTIONS" | rofi -dmenu \
    -p "录屏中心" -i \
    -mesg "󰑊 全屏/区域可选 | 点击状态栏停止" \
    -theme-str 'mainbox { children: [ "message", "listview" ]; }' \
    -theme-str 'entry { enabled: false; }' \
    -theme-str 'message { margin: 0 0 10px 0; padding: 8px; border-radius: 10px; border: 2px solid; border-color: inherit; }' \
    -theme-str 'listview { lines: 6; fixed-height: true; }')

[[ -z "$CHOSEN" ]] && exit 0

# --- 执行录制与计时函数 ---
start_record() {
    local fmt=$1
    local mode=$2  # screen 或 region
    local start_time=$(date +%s)
    local timestamp=$(date +%Y%m%d_%H%M%S)
    local out="$SAVE_DIR/rec_$timestamp.$fmt"

    if [ "$fmt" == "gif" ]; then
        local target_out="$SAVE_DIR/rec_$timestamp.gif"
        out="/tmp/gif_tmp_$timestamp.mp4"
    fi

    local gsr_args=(-f 60 -a "default_output" -o "$out")
    if [ "$mode" == "region" ]; then
        if ! command -v slurp &>/dev/null; then
            notify-send "缺少依赖" "区域录制需要 slurp" -u critical -a "Recorder"
            return 1
        fi
        local geom
        geom=$(slurp -f "%wx%h+%x+%y" 2>/dev/null)
        [[ -z "$geom" ]] && exit 0
        # 兼容旧版 slurp 默认输出 "X,Y WxH" -> 转为 "WxH+X+Y"
        if [[ "$geom" == *","* ]]; then
            geom=$(echo "$geom" | awk '{split($1,a,","); print $2"+"a[1]"+"a[2]}')
        fi
        # 偶数化：H.264(yuv420p)色度采样要求宽高偏移全偶数，
        # 奇数会被编码器四舍五入并垫黑边（GIF 上下黑条即此而来）
        if [[ "$geom" =~ ^([0-9]+)x([0-9]+)\+([0-9]+)\+([0-9]+)$ ]]; then
            local w=$((BASH_REMATCH[1] / 2 * 2)) h=$((BASH_REMATCH[2] / 2 * 2))
            local x=$((BASH_REMATCH[3] / 2 * 2)) y=$((BASH_REMATCH[4] / 2 * 2))
            geom="${w}x${h}+${x}+${y}"
        fi
        gsr_args=(-w "$geom" "${gsr_args[@]}")
        notify_msg="区域 $geom"
        # gsr 会把过矮区域按对齐高度居中垫黑（46px 选区录成 128px 高），
        # GIF 按选中比例居中裁回：期望高 = sel_h*1280/sel_w 取偶
        if [[ "$geom" =~ ^([0-9]+)x([0-9]+)\+ ]]; then
            gif_crop_h=$(( BASH_REMATCH[2] * 1280 / BASH_REMATCH[1] / 2 * 2 ))
            [ "$gif_crop_h" -lt 2 ] && gif_crop_h=2
        else
            gif_crop_h=0
        fi
    else
        gsr_args=(-w screen "${gsr_args[@]}")
        notify_msg="全屏"
    fi

    gpu-screen-recorder "${gsr_args[@]}" 2> "$LOG_FILE" &
    
    sleep 1.2
    if ! pgrep -f "gpu-screen-recorder" > /dev/null; then
        ERR=$(tr -d '\0' < "$LOG_FILE" | tail -n 2)
        notify-send "录屏启动失败" "$ERR" -u critical -a "Recorder"
        return 1
    fi

    notify-send "󰑊 录制开始" "格式: ${fmt^^} | $notify_msg" -t 2000 -a "Recorder"

    # 计时子进程
    (
        while pgrep -f "gpu-screen-recorder" > /dev/null; do
            now=$(date +%s)
            elapsed=$((now - start_time))
            printf "%02d:%02d" $((elapsed / 60)) $((elapsed % 60)) > "$STATUS_FILE"
            refresh_waybar
            sleep 1
        done

        # 🔴 额外保障：GIF 转换完成后再次清理并刷新一次信号
        if [ "$fmt" == "gif" ]; then
            notify-send "正在转换 GIF" "请稍候，正在优化画质..." -a "Recorder"
            gif_vf="fps=15,scale=1280:-2:flags=lanczos"
            # 区域模式裁掉 gsr 的居中垫黑；全屏模式源尺寸即准，不裁
            if [ "${gif_crop_h:-0}" -gt 0 ]; then
                gif_vf="$gif_vf,crop=1280:${gif_crop_h}:0:(in_h-${gif_crop_h})/2"
            fi
            ffmpeg -i "$out" -vf "$gif_vf,split[s0][s1];[s0]palettegen[p];[s1][p]paletteuse" "$target_out" -y
            rm "$out"
            notify-send "GIF 转换完成" "已保存至: $target_out" -i video-x-generic -a "Recorder"
        fi
        
        # 确保无论什么格式结束，Waybar 都能收到最终信号
        rm -f "$STATUS_FILE"
        refresh_waybar
    ) &
}

case "$CHOSEN" in
    *"MP4 全屏"*) start_record "mp4" "screen" ;;
    *"MKV 全屏"*) start_record "mkv" "screen" ;;
    *"GIF 全屏"*) start_record "gif" "screen" ;;
    *"MP4 区域"*) start_record "mp4" "region" ;;
    *"MKV 区域"*) start_record "mkv" "region" ;;
    *"GIF 区域"*) start_record "gif" "region" ;;
esac
