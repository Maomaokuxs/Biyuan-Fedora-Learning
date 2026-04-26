#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 2] 基础运行环境与三方仓库配置${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # 1. 确保 dnf-plugins-core 已安装 (提供 copr 命令支持)
    echo -e "${YELLOW}>> 正在预装系统插件支持...${NC}"
    sudo dnf install -y dnf-plugins-core

    # 2. 启用指定的 Copr 仓库
    # 仓库地址: hermitfeather/hyprland
    echo -e "${BLUE}>> 正在启用三方仓库 [hermitfeather/hyprland] ...${NC}"
    if sudo dnf copr enable -y hermitfeather/hyprland; then
        echo -e "${GREEN}✅ Copr 仓库已成功启用。${NC}"
    else
        echo -e "${RED}❌ 无法启用 Copr 仓库，请检查网络连接。${NC}"
        # 如果启用失败，脚本会继续尝试安装官方源有的包
    fi

    # 3. 核心工具包列表
    # 包含了：配置管理(stow), 终端(kitty), 视觉引擎(hellwal, swww), 
    # 数据解析(jq) 以及图片处理(ImageMagick)
    local pkgs=(
        stow figlet git curl wget unzip 
        kitty fastfetch jq 
        ImageMagick swww hellwal
    )
    
    echo -e "${YELLOW}>> 正在通过新仓库安装基础依赖包 (含 Hellwal)...${NC}"
    
    # 4. 执行统一安装
    if sudo dnf install -y "${pkgs[@]}"; then
        echo -e "${GREEN}✅ 所有基础软件包安装成功。${NC}"
    else
        echo -e "${RED}❌ 部分软件包安装失败。可能是由于仓库同步延迟，建议手动运行 dnf update。${NC}"
        # 返回 1 允许上层脚本感知失败
        return 1
    fi

    # 5. 验证安装结果
    if command -v hellwal &> /dev/null; then
        echo -e "${GREEN}✅ 视觉引擎 Hellwal 已就绪。${NC}"
    else
        echo -e "${RED}⚠️  警告: 在路径中未找到 hellwal，请检查是否需要重启 Shell。${NC}"
    fi
}