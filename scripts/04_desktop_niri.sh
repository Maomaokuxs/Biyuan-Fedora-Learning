#!/bin/bash
# 文件位置: scripts/04_desktop_niri.sh

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] Niri 桌面环境自动化部署${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. 调用独立显卡驱动脚本 (替换原来的冗余代码) ---
    local GPU_SCRIPT="$REPO_DIR/scripts/03_gpu_drivers.sh"
    if [ -f "$GPU_SCRIPT" ]; then
        echo -e "${YELLOW}>> 正在调用外部显卡驱动配置模块...${NC}"
        chmod +x "$GPU_SCRIPT"
        source "$GPU_SCRIPT"
        # 注意：这里假设 03_gpu_drivers.sh 中定义了 setup_gpu 或是直接执行逻辑
        # 如果 03 脚本只是纯命令，source 它就会直接运行；如果里面是函数，请在此处调用函数名
    else
        echo -e "${RED}⚠️ 错误: 找不到显卡脚本 $GPU_SCRIPT，尝试继续安装桌面...${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 2. 安装 Niri 及核心组件 ---
    echo -e "${YELLOW}>> 正在安装 Niri 窗口管理器及周边生态环境...${NC}"
    sudo dnf install -y niri waybar rofi-wayland kitty fcitx5 fcitx5-chinese-addons stow
    echo -e "${GREEN}✅ 基础软件包安装完毕。${NC}"

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. Biyuan 极简配置部署菜单 (二选一) ---
    echo -e "${YELLOW}==== 初始配置部署模式 ====${NC}"
    echo "  1) ☁️  同步仓库最新配置 (Git -> Local) [推荐：使用 Stow 软链接]"
    echo "  2) 📁  物理脱离 (断开链接并还原物理文件) [用于独立测试]"
    echo "  0) ⏭️  跳过配置部署"
    read -p "选择模式 [0-2]: " deploy_mode

    if [[ "$deploy_mode" =~ ^[1-2]$ ]]; then
        echo -e "${YELLOW}>> 正在执行配置部署...${NC}"
        
        for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
            local target_dir="$HOME/.config/$module"
            [[ "$module" == "colors" ]] && target_dir="$HOME/.cache/hellwal"

            [ -e "$target_dir" ] && rm -rf "$target_dir"

            if [ "$deploy_mode" == "1" ]; then
                cd "$DOTFILES_DIR" && stow -t ~ "$module" 2>/dev/null
                echo -e "  [🔗 链接] $module"
            elif [ "$deploy_mode" == "2" ]; then
                mkdir -p "$target_dir"
                cp -rf "$DOTFILES_DIR/$module/." "$target_dir/"
                echo -e "  [📁 物理] $module"
            fi
        done
        echo -e "${GREEN}✅ 所有的配置文件部署完毕！${NC}"

        # --- 4. 自动化色彩与壁纸初始化 (核心新增) ---
        echo -e "\n${BLUE}>> 正在初始化桌面视觉效果 (Hellwal & Wallpaper)...${NC}"
        local INIT_WALL="$DOTFILES_DIR/niri/.config/niri/scripts/init-wallpaper.sh"
        
        if [ -f "$INIT_WALL" ]; then
            chmod +x "$INIT_WALL"
            # 使用 bash 执行以确保环境纯净
            bash "$INIT_WALL"
            echo -e "${GREEN}✅ 桌面色彩初始化完成。${NC}"
        else
            echo -e "${RED}⚠️ 警告: 找不到初始化脚本 $INIT_WALL，跳过色彩生成。${NC}"
        fi
    else
        echo -e "${YELLOW}>> 已跳过配置部署及壁纸初始化。${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 5. 注册全局维护命令 by-mgr ---
    echo -e "${BLUE}>> 正在注册全局系统维护命令: by-mgr${NC}"
    local BIN_DIR="$HOME/.local/bin"
    mkdir -p "$BIN_DIR"
    
    if [ -f "$REPO_DIR/scripts/by-mgr" ]; then
        cp "$REPO_DIR/scripts/by-mgr" "$BIN_DIR/by-mgr"
        chmod +x "$BIN_DIR/by-mgr"
        
        local SHELL_RC="$HOME/.bashrc"
        [[ $SHELL == *"zsh"* ]] && SHELL_RC="$HOME/.zshrc"
        
        if ! grep -q "$BIN_DIR" "$SHELL_RC"; then
            echo -e "\n# Biyuan CLI Tools" >> "$SHELL_RC"
            echo "export PATH=\"\$HOME/.local/bin:\$PATH\"" >> "$SHELL_RC"
        fi
        echo -e "${GREEN}✅ 命令部署成功。重启终端输入 'by-mgr' 即可使用。${NC}"
    fi
}