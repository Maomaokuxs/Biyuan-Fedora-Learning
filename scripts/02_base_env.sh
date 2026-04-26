#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 基础运行环境与视觉引擎安装${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # 核心工具包列表
    # 包含了：配置管理(stow), 终端(kitty), 视觉(hellwal, swww, ImageMagick), 工具(jq, git, wget等)
    local pkgs=(
        stow figlet git curl wget unzip 
        kitty fastfetch jq
        ImageMagick swww hellwal
    )
    
    echo -e "${YELLOW}>> 正在同步官方仓库并安装基础依赖...${NC}"
    
    # 使用 sudo dnf install，确保所有软件安装成功
    if sudo dnf install -y "${pkgs[@]}"; then
        echo -e "${GREEN}✅ 所有基础软件包安装成功。${NC}"
    else
        echo -e "${RED}❌ 部分软件包安装失败，请检查网络或仓库源。${NC}"
        return 1
    fi

    # 验证 hellwal 是否可用
    if command -v hellwal &> /dev/null; then
        echo -e "${GREEN}✅ 视觉引擎 Hellwal 已就绪。${NC}"
    fi
}