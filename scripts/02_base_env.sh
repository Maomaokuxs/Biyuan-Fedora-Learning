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
        ["Cernet (联合)"]="mirrors.cernet.edu.cn"
    )

    echo -e "${CYAN}   ID | Mirror Name         | Latency (ms)${NC}"
    echo -e "   --------------------------------------"
    
    # 创建一个临时目录用于存放并发进程的测速结果
    TMP_DIR=$(mktemp -d)
    
    # 1. 并发派发测速任务
    for name in "${!mirrors[@]}"; do
        host=${mirrors[$name]}
        
        # 将()中的逻辑放入后台执行 (&)
        # 用 HTTP 实测代替 ping：ICMP 常被防火墙拦会误报超时，而 dnf 要的本来就是 HTTP；
        # --max-time 6 硬超时（含 DNS），失败记 Timeout
        (
            secs=$(curl -o /dev/null -s --max-time 6 -w "%{time_total}" "http://$host/" 2>/dev/null)
            rc=$?
            if [ $rc -eq 0 ] && [[ "$secs" =~ ^[0-9.]+$ ]]; then
                awk -v s="$secs" 'BEGIN{printf "%.0f", s*1000}' > "$TMP_DIR/$host"
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

    # --- 2. 系统更新 (可跳过：刚装好的系统通常不需要，或稍后手动升) --- #
    read -p "Skip system upgrade to save time? (y/N): " skip_upgrade
    if [[ "$skip_upgrade" =~ ^[Yy]$ ]]; then
        echo -e "${CYAN}>> Skipping system upgrade.${NC}"
    else
        echo -e "${YELLOW}>> Refreshing package cache and upgrading system...${NC}"
        # 使用 --refresh 强制刷新元数据，确保获取到最新的补丁
        sudo dnf upgrade -y --refresh
    fi

    # --- 3. 初始化家目录结构 --- #
    echo -e "${YELLOW}>> Initializing standard user directories...${NC}"
    sudo dnf install -y xdg-user-dirs

    # 强制英文家目录：不跟随系统 locale，避免生成 桌面/文档 等中文目录
    # （终端、脚本、waypaper 全用英文路径；GNOME 登录时只补缺失不改名，不会弹回去）
    echo -e "${CYAN}>> Forcing English user directories (LANG=C for xdg only)...${NC}"

    # 使用 --force 确保即使在非桌面环境下也能生成目录（LANG 只作用于这一行，不污染后续输出语言）
    LANG=C xdg-user-dirs-update --force

    # 已存在中文目录时搬内容合并，避免中英两套并存（mv -n 不覆盖已有文件）
    # 删除前必须验空（含隐藏文件）：非空一律保留并告警，绝不强删
    for pair in "桌面:Desktop" "文档:Documents" "下载:Downloads" "图片:Pictures" "音乐:Music" "视频:Videos" "公共:Public" "模板:Templates"; do
        zh="$HOME/${pair%%:*}"; en="$HOME/${pair##*:}"
        if [ -d "$zh" ] && [ "$zh" != "$en" ]; then
            mkdir -p "$en"
            mv -n "$zh"/* "$en"/ 2>/dev/null
            if [ -z "$(ls -A "$zh" 2>/dev/null)" ]; then
                rmdir "$zh" && echo -e "${GREEN}✅ Merged $zh -> $en${NC}"
            else
                echo -e "${YELLOW}⚠️  $zh 非空已保留，请手动确认残留文件后再删${NC}"
            fi
        fi
    done

    # 验证并创建自定义的额外路径
    # 注意：这里我们手动创建的路径建议保持英文，方便终端 CD 操作，不建议随语言改变
    mkdir -p "$HOME/Documents/github"
    mkdir -p "$HOME/Pictures/wallpapers"

    # 0. 字体三方源：自打包字体（nerd/sarasa/maple/霞鹜文楷）先启用，失败回落官方+assets
    echo -e "${CYAN}>> Enabling biyuan/software COPR repository (fonts)...${NC}"
    if sudo dnf copr enable -y biyuan/software; then
        echo -e "${GREEN}✅ Repository [biyuan/software] enabled.${NC}"
    else
        echo -e "${YELLOW}⚠️  Failed to enable biyuan/software, fonts fall back to official repo + assets.${NC}"
    fi

    # 1. 基础系统工具与 Fedora 仓库字体包
    # JetBrains Mono（原生）、jetbrainsmono-nerd-fonts（图标，waybar/kitty 必需）、
    # sarasa-gothic-fonts（更纱黑体，中文终端对齐）、Noto Emoji/CJK
    local pkgs=(
        dnf-plugins-core figlet git curl wget
        fzf
        jetbrains-mono-fonts-all.noarch
        jetbrainsmono-nerd-fonts.noarch
        sarasa-gothic-fonts.noarch
        fontawesome-6-free-fonts.noarch
        google-noto-sans-yi-fonts.noarch
        google-noto-emoji-fonts.noarch
        google-noto-sans-cjk-fonts.noarch
    )
    
    echo -e "${YELLOW}>> Installing base tools and official repository fonts...${NC}"
    # 字体包版本间常改名/缺包，用 --skip-unavailable 保流程不炸，缺的下面验出来单独报
    sudo dnf install -y "${pkgs[@]}" --skip-unavailable

    # --- 3.5 字体验收入口：缺啥报啥，不静默带过 --- #
    echo -e "${CYAN}>> Verifying fonts...${NC}"
    local missing=()
    fc-list 2>/dev/null | grep -qi "JetBrainsMono Nerd Font" || missing+=("jetbrainsmono-nerd-fonts（图标，waybar/kitty 会掉图标）")
    fc-list 2>/dev/null | grep -qi "Sarasa" || missing+=("sarasa-gothic-fonts（中文终端对齐）")
    fc-list 2>/dev/null | grep -qi "Font Awesome 6 Free" || missing+=("fontawesome-6-free-fonts（kitty 图标区）")
    fc-list 2>/dev/null | grep -qi "Noto Sans Yi" || missing+=("google-noto-sans-yi-fonts（彝文歌词）")
    fc-list 2>/dev/null | grep -qi "Noto Sans CJK" || missing+=("google-noto-sans-cjk-fonts（中文）")
    if [ ${#missing[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ Fonts OK.${NC}"
    else
        echo -e "${YELLOW}⚠️  以下字体缺失，请手动补装后重跑本脚本或执行 fc-cache -f：${NC}"
        printf '   - %s\n' "${missing[@]}"
    fi

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

    # --- 5. 硬件访问组：ddcutil 外屏亮度要读 /dev/i2c-*，缺组即 EACCES ---
    if getent group i2c >/dev/null 2>&1; then
        if id -nG "$USER" 2>/dev/null | grep -qw i2c; then
            echo -e "${GREEN}✅ 已在 i2c 组。${NC}"
        else
            sudo usermod -aG i2c "$USER"
            echo -e "${YELLOW}⚠️  已加入 i2c 组，需重登录生效（ddcutil 外屏亮度）。${NC}"
        fi
    else
        echo -e "${YELLOW}⚠️  无 i2c 组（ddcutil 未装？），跳过。${NC}"
    fi

    echo -e "${GREEN}✅ Base environment and font configuration successful.${NC}"
}