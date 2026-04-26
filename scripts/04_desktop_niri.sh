#!/bin/bash

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [阶段 4] 部署 Niri 桌面环境与色彩初始化${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. 默认壁纸初始化与取色 ---
    local USER_WALL_DIR="$HOME/Pictures/Wallpapers"
    mkdir -p "$USER_WALL_DIR"
    
    # 指向仓库中的默认资源 (请确保仓库下有 assets/default_wallpaper.png)
    local REPO_DEFAULT_WALL="$REPO_DIR/assets/default_wallpaper.png"
    
    if [ -f "$REPO_DEFAULT_WALL" ]; then
        local wall_name="default_initial_wallpaper.png"
        local target_wall="$USER_WALL_DIR/$wall_name"
        
        # 复制到用户目录
        cp "$REPO_DEFAULT_WALL" "$target_wall"
        
        echo -e "${BLUE}>> 正在执行初始色彩提取 (Hellwal)...${NC}"
        if command -v hellwal &> /dev/null; then
            # 仅触发生成脚本，不涉及仓库提交
            hellwal -i "$target_wall" > /dev/null 2>&1
            
            # 记录当前壁纸状态供分发脚本使用
            echo "$target_wall" > "$HOME/.cache/current_wallpaper"
            echo -e "${GREEN}✅ 本地颜色配置文件已生成至 ~/.cache/hellwal/${NC}"
        else
            echo -e "${RED}❌ 错误: 未找到 hellwal 命令，请确保在基础环境阶段已安装。${NC}"
        fi
    else
        echo -e "${YELLOW}>> [警告] 仓库内未找到 assets/default_wallpaper.png，跳过色彩生成。${NC}"
    fi

    # --- 2. 应用 Dotfiles 链接 ---
    echo -e "${BLUE}>> 正在部署 Niri, Waybar, Rofi 相关配置...${NC}"
    cd "$DOTFILES_DIR"
    
    # 按照你的要求，这里只链接应用配置，不涉及 colors 仓库模块
    for mod in niri waybar rofi mako kitty; do
        if [ -d "$mod" ]; then
            stow -t ~ "$mod" 2>/dev/null
            echo -e "${GREEN}  [OK] 链接模块: $mod${NC}"
        fi
    done

    echo -e "${GREEN}✅ Niri 桌面环境部署完成！${NC}"
}