#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}          Base Environment & Core Fonts${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. 软件镜像源优化 (并发测速/选择/恢复) ---
    echo -e "${BLUE}>> Network optimization: Parallel mirror speed test & selection...${NC}"
    
    # 定义国内主流镜像站
    declare -A mirrors=(
        ["Tuna (Tsinghua)"]="mirrors.tuna.tsinghua.edu.cn"
        ["Aliyun"]="mirrors.aliyun.com"
        ["USTC (Zhongkeda)"]="mirrors.ustc.edu.cn"
    )

    echo -e "${CYAN}   ID | Mirror Name         | Latency (ms)${NC}"
    echo -e "   --------------------------------------"
    
    # 创建一个临时目录用于存放并发进程的测速结果
    TMP_DIR=$(mktemp -d)
    
    # 1. 并发派发测速任务
    for name in "${!mirrors[@]}"; do
        host=${mirrors[$name]}
        
        # 将()中的逻辑放入后台执行 (&)
        # 优化 ping 参数：-c 3 发3个包，-w 3 设置整个 ping 命令硬超时为3秒，防止死锁
        (
            latency=$(ping -c 3 -w 3 "$host" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
            if [ -n "$latency" ]; then
                echo "$latency" > "$TMP_DIR/$host"
            else
                echo "Timeout" > "$TMP_DIR/$host"
            fi
        ) &
    done

    # 核心魔法：挂起主脚本，等待所有后台 & 任务执行完毕！
    # 这样总耗时最长也就 3 秒左右
    wait

    local i=1
    local ids=()
    local hosts=()
    
    # 2. 收集结果并格式化输出
    for name in "${!mirrors[@]}"; do
        host=${mirrors[$name]}
        # 读取临时文件中的结果
        latency=$(cat "$TMP_DIR/$host" 2>/dev/null)
        
        if [ "$latency" != "Timeout" ] && [ -n "$latency" ]; then
            printf "   %d) | %-18s | %s ms\n" "$i" "$name" "$latency"
        else
            printf "   %d) | %-18s | ${RED}Timeout${NC}\n" "$i" "$name"
        fi
        
        ids+=($i)
        hosts+=($host)
        ((i++))
    done

    # 清理临时目录
    rm -rf "$TMP_DIR"

    echo -e "   r) | Restore Official    | (Reset to default)"
    echo -e "   n) | Skip / Keep Current | --"
    echo -e "   --------------------------------------"

    read -p "Select [1-${#ids[@]} / r / n]: " mirror_choice
    
    # 逻辑分支处理
    if [[ "$mirror_choice" =~ ^[1-9]$ ]] && [ "$mirror_choice" -le "${#ids[@]}" ]; then
        local selected_host=${hosts[$((mirror_choice-1))]}
        echo -e "${YELLOW}>> Switching to $selected_host...${NC}"
        sudo sed -e 's|^metalink=|#metalink=|g' \
            -e "s|^#baseurl=http://download.example/pub/fedora/linux|baseurl=https://$selected_host/fedora|g" \
            -i.bak \
            /etc/yum.repos.d/fedora.repo \
            /etc/yum.repos.d/fedora-updates.repo
        echo -e "${GREEN}✅ Mirror switched to $selected_host.${NC}"

    elif [[ "$mirror_choice" == "r" ]]; then
        echo -e "${YELLOW}>> Restoring official Fedora repositories...${NC}"
        sudo sed -e 's|^#metalink=|metalink=|g' \
            -e 's|^baseurl=https://.*/fedora|#baseurl=http://download.example/pub/fedora/linux|g' \
            -i.bak \
            /etc/yum.repos.d/fedora.repo \
            /etc/yum.repos.d/fedora-updates.repo
        echo -e "${GREEN}✅ Official mirrors restored.${NC}"

    else
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
    # [定位导航逻辑]：自动获取仓库根目录
    # BASH_SOURCE[0] 获取脚本当前路径，dirname 获取目录，最后 cd 进去拿到绝对路径
    local CURRENT_SCRIPT_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    local REPO_ROOT=$(dirname "$CURRENT_SCRIPT_DIR")
    
    # 定义源目录与目标目录
    local SOURCE_FONTS_DIR="$REPO_ROOT/assets/fonts"
    local TARGET_FONTS_DIR="$HOME/.local/share/fonts"

    # 1. 确保目标目录存在
    mkdir -p "$TARGET_FONTS_DIR"

    echo -e "${BLUE}>> 正在定位字体资产...${NC}"
    echo -e "${CYAN}>> 仓库根目录: $REPO_ROOT${NC}"

    # 2. 全量同步逻辑：将 assets/fonts 下的所有内容宽泛地部署到系统
    if [ -d "$SOURCE_FONTS_DIR" ] && [ "$(ls -A "$SOURCE_FONTS_DIR")" ]; then
        echo -e "${YELLOW}>> 正在从 $SOURCE_FONTS_DIR 同步字体...${NC}"
        
        # 使用 -u (仅更新) 和 -p (保留权限)
        cp -upvf "$SOURCE_FONTS_DIR"/* "$TARGET_FONTS_DIR/" 2>/dev/null

        echo -e "${CYAN}>> 正在刷新系统字体缓存...${NC}"
        fc-cache -f "$TARGET_FONTS_DIR"
        
        echo -e "${GREEN}✅ 字体资产部署完成。${NC}"
    else
        echo -e "${RED}❌ 错误: 找不到源目录或目录下无文件: $SOURCE_FONTS_DIR${NC}"
    fi

    echo -e "${GREEN}✅ Base environment and font configuration successful.${NC}"
}