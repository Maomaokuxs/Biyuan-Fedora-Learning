#!/bin/bash

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 基础运行环境与核心工具${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # 核心包与美化包列表
    local pkgs=(
        stow figlet git curl wget unzip 
        kitty fastfetch
        ImageMagick  # hellwal 处理图片通常需要这个
    )
    
    echo ">> 正在安装基础依赖包..."
    sudo dnf install -y "${pkgs[@]}"

    # --- 安装 Hellwal ---
    echo -e "${BLUE}>> 正在检查并安装 Hellwal 色彩引擎...${NC}"
    if ! command -v hellwal &> /dev/null; then
        # 如果 hellwal 在 Fedora 官方源里有，可以直接用 dnf：
        # sudo dnf install -y hellwal
        
        # 补充方案：如果 hellwal 是 Rust 写的或基于 Cargo：
        if command -v cargo &> /dev/null; then
            cargo install hellwal
        else
            echo -e "${YELLOW}>> 未找到 hellwal，尝试通过 Copr 或其他源安装...${NC}"
            # 在这里填入你实际安装 hellwal 的准确命令，例如：
            # sudo dnf copr enable -y some_repo/hellwal
            # sudo dnf install -y hellwal
        fi
    else
        echo -e "${GREEN}✅ Hellwal 已安装。${NC}"
    fi
}