#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}          Base Environment & Core Fonts${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. 软件镜像源优化 (测速/选择/恢复) ---
    echo -e "${BLUE}>> Network optimization: Mirror speed test & selection...${NC}"
    
    # 定义国内主流镜像站
    declare -A mirrors=(
        ["Tuna (Tsinghua)"]="mirrors.tuna.tsinghua.edu.cn"
        ["Aliyun"]="mirrors.aliyun.com"
        ["USTC (Zhongkeda)"]="mirrors.ustc.edu.cn"
    )

    echo -e "${CYAN}   ID | Mirror Name         | Latency (ms)${NC}"
    echo -e "   --------------------------------------"
    
    local i=1
    local ids=()
    local hosts=()
    
    # 执行测速循环
    for name in "${!mirrors[@]}"; do
        host=${mirrors[$name]}
        # 测试 3 次 ping 取平均值，超时 2 秒
        latency=$(ping -c 3 -W 2 "$host" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
        
        if [ -n "$latency" ]; then
            printf "   %d) | %-18s | %s ms\n" "$i" "$name" "$latency"
        else
            printf "   %d) | %-18s | ${RED}Timeout${NC}\n" "$i" "$name"
        fi
        
        ids+=($i)
        hosts+=($host)
        ((i++))
    done

    echo -e "   r) | Restore Official    | (Reset to default)"
    echo -e "   n) | Skip / Keep Current | --"
    echo -e "   --------------------------------------"

    read -p "Select [1-${#ids[@]} / r / n]: " mirror_choice
    
    # 逻辑分支处理
    if [[ "$mirror_choice" =~ ^[1-9]$ ]] && [ "$mirror_choice" -le "${#ids[@]}" ]; then
        # 选择国内源
        local selected_host=${hosts[$((mirror_choice-1))]}
        echo -e "${YELLOW}>> Switching to $selected_host...${NC}"
        sudo sed -e 's|^metalink=|#metalink=|g' \
            -e "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://$selected_host/fedora|g" \
            -i.bak \
            /etc/yum.repos.d/fedora.repo \
            /etc/yum.repos.d/fedora-updates.repo
        echo -e "${GREEN}✅ Mirror switched to $selected_host.${NC}"

    elif [[ "$mirror_choice" == "r" ]]; then
        # 恢复官方源：撤销注释并还原 metalink
        echo -e "${YELLOW}>> Restoring official Fedora repositories...${NC}"
        sudo sed -e 's|^#metalink=|metalink=|g' \
            -e 's|^baseurl=https://.*/fedora|#baseurl=http://download.example/pub/fedora/linux|g' \
            -i.bak \
            /etc/yum.repos.d/fedora.repo \
            /etc/yum.repos.d/fedora-updates.repo
        echo -e "${GREEN}✅ Official mirrors restored.${NC}"

    else
        # 默认不切换 (n 或任意输入)
        echo -e "${CYAN}>> No changes applied.${NC}"
    fi

    # --- 2. 系统更新 (确保安装前系统版本最新) --- #
    echo -e "${YELLOW}>> Refreshing package cache and upgrading system...${NC}"
    # 使用 --refresh 强制刷新元数据，确保获取到最新的补丁
    sudo dnf upgrade -y --refresh

    # --- 3. 初始化家目录结构 --- #
    echo -e "${YELLOW}>> Initializing standard user directories...${NC}"
    sudo dnf install -y xdg-user-dirs

    # 通过导出当前 LANG 变量，强制 xdg-user-dirs-update 识别系统语言
    # 这会确保生成的文件夹名称与你当前的系统语言完美匹配
    export LANG=$(localectl status | grep "System Locale" | cut -d= -f2)
    
    echo -e "${CYAN}>> Detected locale: $LANG. Syncing directories...${NC}"
    
    # 使用 --force 确保即使在非桌面环境下也能根据语言生成目录
    xdg-user-dirs-update --force

    # 验证并创建自定义的额外路径
    # 注意：这里我们手动创建的路径建议保持英文，方便终端 CD 操作，不建议随语言改变
    mkdir -p "$HOME/Documents/github"
    mkdir -p "$HOME/Pictures/wallpapers"

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

    # --- 4. Iosevka Nerd Font 本地部署 --- #
    # 不依赖外部 REPO_DIR，改为根据脚本位置自动推导
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