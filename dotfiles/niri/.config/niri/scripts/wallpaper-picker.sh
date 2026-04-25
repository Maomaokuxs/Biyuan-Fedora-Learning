#!/bin/bash

# 1. 定义你的壁纸存放路径
WALL_DIR="$HOME/Pictures/wallpapers"

# 2. 扫描文件夹并传递给 Rofi
# -dmenu: 让 Rofi 进入选择模式
# -i: 忽略大小写
# -p: 设置提示文字
SELECTED=$(ls "$WALL_DIR" | rofi -dmenu -i -p "选择壁纸 ✨")

# 3. 如果用户没按 Esc（即选中了文件），则执行同步
if [ -n "$SELECTED" ]; then
    FULL_PATH="$WALL_DIR/$SELECTED"
    
    # 调用你那个已经调通的同步脚本
    bash "$HOME/.config/niri/scripts/theme-sync.sh" "$FULL_PATH"
    
    # 可选：发送一个桌面通知
    notify-send "主题已同步" "壁纸已更换为: $SELECTED" -i "$FULL_PATH"
fi
