#!/bin/bash
# 文件位置: scripts/02_base_env.sh

setup_base() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}          Base Environment & Core Fonts${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. 软件镜像源优化 (多线程并行版) ---
    echo -e "${BLUE}>> Network optimization: Parallel mirror speed test...${NC}"
    
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
    local temp_results="/tmp/mirror_ping_results"
    rm -f "$temp_results"

    # [核心优化]：并行执行测速
    for name in "${!mirrors[@]}"; do
        host=${mirrors[$name]}
        # 记录顺序，方便后续展示
        hosts+=($host)
        ids+=($i)
        
        # 将 ping 任务丢入后台并行执行，结果写入临时文件
        (
            # -c 2 足够测出延迟，减少总发包量
            latency=$(ping -c 2 -W 2 "$host" 2>/dev/null | tail -1 | awk '{print $4}' | cut -d '/' -f 2)
            if [ -z "$latency" ]; then
                echo "$name|${RED}Timeout${NC}" >> "$temp_results"
            else
                echo "$name|$latency ms" >> "$temp_results"
            fi
        ) &
        ((i++))
    done

    echo -e "${YELLOW}>> Testing all mirrors simultaneously...${NC}"
    wait # 等待所有后台任务完成

    # 按照 ID 顺序读取结果并打印
    for j in "${!hosts[@]}"; do
        name=$(echo "${!mirrors[@]}" | cut -d' ' -f$((j+1)))
        # 从临时文件中提取对应镜像的结果
        res=$(grep "^$name|" "$temp_results" | cut -d'|' -f2)
        printf "   %d) | %-18s | %s\n" "$((j+1))" "$name" "$res"
    done
    rm -f "$temp_results"

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