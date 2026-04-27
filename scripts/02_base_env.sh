#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 2] Base Environment & Core Fonts${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # 1. 基础系统工具与 Fedora 仓库字体包
    # 包含了你指定的 JetBrains Mono, Noto Emoji, Noto CJK
    local pkgs=(
        dnf-plugins-core figlet git curl wget
        jetbrains-mono-fonts-all.noarch
        google-noto-emoji-fonts.noarch
        google-noto-sans-cjk-fonts.noarch
    )
    
    echo -e "${YELLOW}>> Installing base tools and official repository fonts...${NC}"
    sudo dnf install -y "${pkgs[@]}"

    # --- 2. Iosevka Nerd Font 本地部署 ---
    # 【修复重点】：不依赖外部 REPO_DIR，改为根据脚本位置自动推导
    local CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    local REPO_ROOT=$(dirname "$CURRENT_SCRIPT_DIR")
    local REPO_FONT_SOURCE="$REPO_ROOT/assets/fonts/IosevkaNerdFont-Regular.ttf"
    
    local FONT_DIR="$HOME/.local/share/fonts"
    
    # 确保目标目录物理存在
    mkdir -p "$FONT_DIR"

    echo -e "${BLUE}>> Checking Iosevka font status...${NC}"
    
    if fc-list | grep -qi "Iosevka" || [ -f "$FONT_DIR/IosevkaNerdFont-Regular.ttf" ]; then
        echo -e "${GREEN}✅ Iosevka font already registered or file exists. Skipping installation.${NC}"
    else
        # 增加调试信息：打印出脚本尝试查找的真实路径
        echo -e "${CYAN}>> Search path: $REPO_FONT_SOURCE${NC}"

        if [ -f "$REPO_FONT_SOURCE" ]; then
            echo -e "${YELLOW}>> Copying font file from repository assets...${NC}"
            # 使用 -p 保留权限，使用 -f 强制覆盖
            cp -pf "$REPO_FONT_SOURCE" "$FONT_DIR/"
            
            echo -e "${CYAN}>> Refreshing system font cache...${NC}"
            fc-cache -f "$FONT_DIR" > /dev/null
            echo -e "${GREEN}✅ Iosevka font local deployment completed.${NC}"
        else
            echo -e "${RED}❌ Error: Font asset not found at physical path!${NC}"
            echo -e "${RED}   Please verify if the file exists at: ${BOLD}$REPO_FONT_SOURCE${NC}"
            
            # 自动列出 assets 目录内容帮助排查
            echo -e "${YELLOW}>> Current content of assets/fonts directory:${NC}"
            ls -R "$REPO_ROOT/assets" 2>/dev/null || echo "   (Directory does not exist)"
        fi
    fi

    echo -e "${GREEN}✅ Base environment and font configuration successful.${NC}"
}