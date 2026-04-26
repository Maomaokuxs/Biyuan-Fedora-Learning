#!/bin/bash

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [阶段 4] 部署 Niri 桌面环境与色彩初始化${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. 壁纸初始化 (小写 wallpapers) ---
    local USER_WALL_DIR="$HOME/Pictures/wallpapers"
    mkdir -p "$USER_WALL_DIR"
    
    local REPO_DEFAULT_WALL="$REPO_DIR/assets/default_wallpaper.png"
    local INIT_WALL="$USER_WALL_DIR/default_initial_wallpaper.png"
    
    if [ -f "$REPO_DEFAULT_WALL" ]; then
        echo -e "${BLUE}>> 正在部署初始壁纸资产...${NC}"
        cp "$REPO_DEFAULT_WALL" "$INIT_WALL"
        
        # 主动触发一次 Hellwal 色彩生成
        if command -v hellwal &> /dev/null; then
            echo -e "${BLUE}>> 正在生成初始 Hellwal 色彩配置...${NC}"
            hellwal -i "$INIT_WALL" > /dev/null 2>&1
            # 缓存当前壁纸路径供 Niri 启动脚本使用
            echo "$INIT_WALL" > "$HOME/.cache/current_wallpaper"
            echo -e "${GREEN}✅ 初始色彩生成完成。${NC}"
        fi
    else
        echo -e "${RED}⚠️ 仓库 assets/ 下未找到默认壁纸，跳过色彩初始化。${NC}"
    fi

    # --- 2. 部署 Dotfiles 链接 ---
    echo -e "${BLUE}>> 正在链接应用配置 (Niri, Waybar, Rofi)...${NC}"
    cd "$DOTFILES_DIR"
    
    # 遍历仓库模块进行链接，注意 colors 模块已从仓库中移除，由 hellwal 动态生成
    for mod in niri waybar rofi mako kitty; do
        if [ -d "$mod" ]; then
            stow -t ~ "$mod" 2>/dev/null
            echo -e "${GREEN}  [OK] 链接模块: $mod${NC}"
        fi
    done

    echo -e "${GREEN}✅ Niri 桌面环境部署完成！${NC}"
}