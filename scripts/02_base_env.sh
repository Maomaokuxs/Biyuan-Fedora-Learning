#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 基础运行环境与核心工具安装${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # 1. 核心软件包列表
    # 包含了 Niri 运行所需的图形支持和你的取色分发脚本需要的依赖
    local pkgs=(
        stow figlet git curl wget unzip 
        kitty fastfetch jq
        ImageMagick swww
    )
    
    echo -e "${YELLOW}>> 正在安装基础依赖包...${NC}"
    sudo dnf install -y "${pkgs[@]}"

    # 2. 核心取色引擎 Hellwal 专项处理
    echo -e "${BLUE}>> 正在检查 Hellwal 色彩引擎...${NC}"
    if ! command -v hellwal &> /dev/null; then
        echo -e "${YELLOW}>> 未找到 hellwal，尝试通过 Copr 源安装 (Fedora 推荐方式)...${NC}"
        # 尝试 Fedora 社区常用的 Copr 源（如果这是你常用的方式）
        sudo dnf copr enable -y svenstaro/hellwal || true
        if ! sudo dnf install -y hellwal; then
            echo -e "${RED}⚠️  DNF 安装失败，尝试通过 Cargo (Rust) 编译安装...${NC}"
            if command -v cargo &> /dev/null; then
                cargo install hellwal
            else
                echo -e "${RED}❌ 错误: 未能安装 Hellwal。请手动检查安装源。${NC}"
            fi
        fi
    else
        echo -e "${GREEN}✅ Hellwal 已就绪。${NC}"
    fi

    # 3. 检查并确保 ~/Pictures/Wallpapers 存在
    mkdir -p "$HOME/Pictures/Wallpapers"
    
    echo -e "${GREEN}✅ 基础环境配置完成。${NC}\n"
}