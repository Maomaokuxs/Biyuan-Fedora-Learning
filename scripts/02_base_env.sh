#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    # 纯净基础工具包列表
    local pkgs=(
        figlet git curl wget
    )
    
    echo -e "${YELLOW}>> 正在安装基础系统命令行工具...${NC}"
    
    if sudo dnf install -y "${pkgs[@]}"; then
        echo -e "${GREEN}✅ 基础运行环境部署成功。${NC}"
    else
        echo -e "${RED}❌ 基础环境安装失败，请检查网络。${NC}"
        return 1
    fi
}