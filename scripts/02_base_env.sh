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

    # 2. Iosevka Nerd Font 手动部署
    # 考虑到 GitHub 目录结构复杂，我们采用直接下载关键 .ttf 文件的方式
    local FONT_DIR="$HOME/.local/share/fonts"
    mkdir -p "$FONT_DIR"

    if ! fc-list | grep -qi "Iosevka"; then
        echo -e "${BLUE}>> 正在从 GitHub 部署 Iosevka Nerd Font...${NC}"
        # 这里下载 Iosevka Term Nerd Font 这是一个常用的版本
        local IOSEVKA_URL="https://github.com/ryanoasis/nerd-fonts/raw/master/patched-fonts/Iosevka/Regular/IosevkaNerdFont-Regular.tty"
        # 备注：由于 Iosevka 仓库路径较深，通常建议下载打包好的版本或指定文件
        wget -q --show-progress "$IOSEVKA_URL" -O "$FONT_DIR/IosevkaNerdFont-Regular.ttf"
        
        # 刷新系统字体缓存
        fc-cache -fv > /dev/null
        echo -e "${GREEN}✅ Iosevka 字体部署完成。${NC}"
    else
        echo -e "${GREEN}✅ Iosevka 字体已存在，跳过下载。${NC}"
    fi

    echo -e "${GREEN}✅ 基础环境与字体配置成功。${NC}"
}