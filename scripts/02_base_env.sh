#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 基础环境与核心字体部署${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # 1. 基础系统工具与 Fedora 仓库字体包
    # 包含了你指定的 JetBrains Mono, Noto Emoji, Noto CJK
    local pkgs=(
        dnf-plugins-core figlet git curl wget
        jetbrains-mono-fonts-all.noarch
        google-noto-emoji-fonts.noarch
        google-noto-sans-cjk-fonts.noarch
    )
    
    echo -e "${YELLOW}>> 正在安装基础工具与官方仓库字体...${NC}"
    sudo dnf install -y "${pkgs[@]}"

# 2. Iosevka Nerd Font 本地部署 (从仓库资产安装)
 
    # 优先检查系统中是否已经识别该字体
    if fc-list | grep -qi "Iosevka"; then
        echo -e "${GREEN}✅ Iosevka 字体已在系统中注册，跳过安装。${NC}"
    else
        # 严格检查仓库资产目录中是否存在字体文件
        if [ -f "$REPO_FONT_SOURCE" ]; then
            echo -e "${YELLOW}>> 正在从仓库资产拷贝字体文件...${NC}"
            cp "$REPO_FONT_SOURCE" "$FONT_DIR/"
            
            echo -e "${CYAN}>> 正在刷新系统字体缓存...${NC}"
            fc-cache -f > /dev/null
            echo -e "${GREEN}✅ Iosevka 字体本地部署完成。${NC}"
        else
            echo -e "${RED}❌ 错误: 在仓库中未找到字体资产！${NC}"
            echo -e "${RED}   路径应为: $REPO_FONT_SOURCE${NC}"
            echo -e "${YELLOW}>> 请手动将字体文件放入该路径后重新运行。${NC}"
        fi
    f

    echo -e "${GREEN}✅ 基础环境与字体配置成功。${NC}"
}