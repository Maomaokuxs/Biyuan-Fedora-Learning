#!/bin/bash
# 文件位置: scripts/04_desktop_niri.sh

# prepare_by_mgr — by-mgr 本体就绪（可单独调，幂等）
# install.sh 在 Phase 1 备份之前先调一次（备份改调 by-mgr snapshot，之前必须先有它）；
# 04 第 5 步再调一次确认。顺序说明：原来第 7 步才装 by-mgr，第 5 步部署时它还不存在；
# 现把本体就绪提前到部署之前，stow 在第 4 步已装好，部署条件齐了。
# 二进制来源：优先用仓库里刚构建的 target/release（最新），
# 新 clone 的仓库没有 target/ 时回落到仓库内已跟踪的 scripts/by-mgr。
# 注意：BY_MGR_BIN 故意不用 local——第 6 步和 01 的快照调用都要用它。
prepare_by_mgr() {
    BY_MGR_BIN="$HOME/.local/bin/by-mgr"
    export BY_MGR_BIN
    local by_mgr_src=""
    if [ -x "$REPO_DIR/src/by-mgr-rs/target/release/by-mgr" ]; then
        by_mgr_src="$REPO_DIR/src/by-mgr-rs/target/release/by-mgr"
    elif [ -x "$REPO_DIR/scripts/by-mgr" ]; then
        by_mgr_src="$REPO_DIR/scripts/by-mgr"
    else
        echo -e "${RED}❌ Error: by-mgr binary not found (target/release or scripts/by-mgr).${NC}"
        return 1
    fi
    mkdir -p "$HOME/.local/bin"
    # 已有软链且正好指向选中的二进制时不动（开发机的软链布局不受影响）；
    # 其余情况复制一份实体文件，新机删仓后仍可用。
    if [ -L "$BY_MGR_BIN" ]; then
        local by_mgr_resolved
        by_mgr_resolved=$(readlink -f "$BY_MGR_BIN" 2>/dev/null || true)
        if [ "$by_mgr_resolved" != "$by_mgr_src" ]; then
            rm -f "$BY_MGR_BIN"
            cp "$by_mgr_src" "$BY_MGR_BIN" && chmod +x "$BY_MGR_BIN"
            echo -e "${GREEN}✅ by-mgr deployed to $BY_MGR_BIN${NC}"
        else
            echo -e "${GREEN}✅ by-mgr already ready: $BY_MGR_BIN -> $by_mgr_src${NC}"
        fi
    elif [ -f "$BY_MGR_BIN" ]; then
        if ! cmp -s "$BY_MGR_BIN" "$by_mgr_src"; then
            cp -f "$by_mgr_src" "$BY_MGR_BIN" && chmod +x "$BY_MGR_BIN"
            echo -e "${GREEN}✅ by-mgr updated at $BY_MGR_BIN${NC}"
        else
            echo -e "${GREEN}✅ by-mgr already ready: $BY_MGR_BIN${NC}"
        fi
    else
        cp "$by_mgr_src" "$BY_MGR_BIN" && chmod +x "$BY_MGR_BIN"
        echo -e "${GREEN}✅ by-mgr deployed to $BY_MGR_BIN${NC}"
    fi
    if ! "$BY_MGR_BIN" --version &>/dev/null; then
        echo -e "${RED}❌ Error: by-mgr binary does not run: $BY_MGR_BIN${NC}"
        return 1
    fi
    # 仓库定位：显式告诉 by-mgr 本次安装用的仓库，避免它靠 exe 位置猜；
    # repo.state 不存在（新机）时按本次仓库预写一份，跳过首次运行的确认提问；
    # 已有记录时一律不动，换仓的停机保护仍由 by-mgr 自己把关。
    export BY_MGR_REPO="$REPO_DIR"
    if [ ! -f "$HOME/.config/by-mgr/repo.state" ]; then
        local repo_id
        repo_id=$(grep '^id=' "$REPO_DIR/.by-mgr-root" 2>/dev/null | cut -d= -f2-)
        if [ -n "$repo_id" ]; then
            mkdir -p "$HOME/.config/by-mgr"
            printf 'id=%s\npath=%s\nmode=repo\nsource=config\n' "$repo_id" "$REPO_DIR" > "$HOME/.config/by-mgr/repo.state"
        fi
    fi
}

install_desktop_niri() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 3] Niri Desktop Environment Deployment${NC}"
    echo -e "${BLUE}=====================================================${NC}"

    # --- 1. 调用基础环境 ---
    if command -v setup_base &> /dev/null; then
        echo -e "${YELLOW}>> Checking and deploying base runtime environment...${NC}"
        setup_base
    else
        echo -e "${RED}❌ Error: 'setup_base' function not found!${NC}"
    fi

    # --- 2. 调用独立显卡驱动 ---
    if command -v setup_gpu_drivers &> /dev/null; then
        echo -e "${YELLOW}>> Loading external GPU driver configuration module...${NC}"
        setup_gpu_drivers
    else
        echo -e "${RED}❌ Error: 'setup_gpu_drivers' function not found!${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. 配置三方仓库：只留作者自维护的 luisbocanegra OBS（kde-material-you-colors）---
    # 注：hyprland 生态（hyprlock/idle/picker）、starship、gpu-screen-recorder 都在
    #      biyuan/software（已在 02 启用）里有最新版，eddievs/hyprland、atim/starship、
    #      ackerman/nexus 三个源不再启用。
    # 启用 KDE Material You 配色仓库 (theme-sync 依赖)
    # 注: kde-material-you-colors 官方发布在 openSUSE Build Service (OBS),
    #      luisbocanegra/kde-material-you-colors COPR 可能不存在, 以 OBS repofile 为准。
    # 保留原 COPR 启用可见 (仅注释, 不删减):
    # sudo dnf copr enable -y luisbocanegra/kde-material-you-colors
    # 启用输出太杂，不展示过程，只静默执行、事后用 repolist 检查是否启用成功。
    sudo dnf config-manager addrepo \
        --from-repofile=https://download.opensuse.org/repositories/home:luisbocanegra/Fedora_44/home:luisbocanegra.repo &>/dev/null || \
        sudo dnf config-manager --add-repo \
        https://download.opensuse.org/repositories/home:luisbocanegra/Fedora_44/home:luisbocanegra.repo &>/dev/null
    if dnf repolist 2>/dev/null | grep -q "^home_luisbocanegra"; then
        echo -e "${GREEN}✅ Repository [home:luisbocanegra] enabled.${NC}"
    else
        echo -e "${RED}❌ Failed to enable repository [home:luisbocanegra].${NC}"
    fi

    # --- 4. 安装 Niri 及桌面/视觉生态组件 ---
    echo -e "${YELLOW}>> Setting up multimedia and recording environment...${NC}"
    
    # 1. 优先解决 FFmpeg 冲突 (录屏工具的基石)
    if rpm -q ffmpeg-free &>/dev/null; then
        echo -e "${CYAN}>> Swapping to full-featured ffmpeg for NVENC support...${NC}"
        hx sudo dnf swap -y ffmpeg-free ffmpeg --allowerasing
    fi

    # 2. 预清理孤立冲突包：kmime 无人依赖，却与 akonadi 链拉入的 kf6-kmime 文件冲突，
    # 不清则整个事务回滚（--allowerasing 也救不了，因为删了没人要的包 solver 不敢动）。
    # 有人依赖时不动，交回 --allowerasing 处理。
    # 注意：rpm 的“没有软件包需要”走 stdout，只能用退出码判断（非零=无人要）。
    if rpm -q kmime &>/dev/null && ! rpm -q --whatrequires kmime &>/dev/null; then
        echo -e "${CYAN}>> Removing orphaned kmime (conflicts with kf6-kmime)...${NC}"
        hx sudo dnf remove -y kmime
    fi

    # 3. 执行补全安装
    # 核心：niri (窗口管理器), waybar (状态栏), rofi (2.x 原生 Wayland 启动器)
    # 美化：awww (壁纸后端), hellwal (色彩方案生成), kde-material-you-colors (KDE M3配色), starship (终端美化)，cava（终端可视化音乐实现）
    # 功能：fcitx5 (输入法), kanshi (屏幕切换), dolphin (文件管理), mako (通知通知), hyprlock/idle (锁屏与休眠)，gwenview（图片查看器），
    # blueman（蓝牙管理工具），btop（资源占用查看工具)，kate（文本编辑器）,ddcutil(显示器亮度调整)，NetworkManager-tui（nmtui 网络连接工具）
    # kf6-kwallet libsecret（密钥及管理工具）ncdu(终端磁盘文件占用查看器) ranger（终端文件管理器）
    
    local niri_pkgs=(
        niri waybar quickshell rofi stow unzip kitty 
        fastfetch jq awww hellwal kanshi 
        waypaper starship hyprlock hypridle 
        gpu-screen-recorder libnotify mako 
        grim slurp ImageMagick wl-clipboard copyq hyprpicker
        fcitx5 fcitx5-chinese-addons 
        xdg-desktop-portal-kde xdg-desktop-portal-wlr
        polkit-kde firefox cava dolphin gwenview
        blueman btop kate ddcutil NetworkManager-tui 
        kf6-kwallet libsecret ncdu ranger
        kde-material-you-colors playerctl brightnessctl python3-requests
    )

    echo -e "${YELLOW}>> Deploying Niri ecosystem components...${NC}"
    # 先刷新软件源缓存：刚启用一批 COPR，直接装可能读到旧元数据
    sudo dnf makecache 2>/dev/null || sudo dnf makecache --refresh
    # --skip-unavailable 缺包不炸；--allowerasing 允许换掉冲突包
    # （如 kf6-kmime 与 kmime 文件冲突，不加则整个事务回滚、一个都装不上）
    x sudo dnf install -y "${niri_pkgs[@]}" --skip-unavailable --allowerasing

    # --- 4.0 装完验包：--skip-unavailable 会静默跳过，缺啥点名，不带过 ---
    echo -e "${CYAN}>> Verifying packages...${NC}"
    local miss_pkgs=()
    for p in "${niri_pkgs[@]}"; do
        rpm -q "$p" &>/dev/null || miss_pkgs+=("$p")
    done
    if [ ${#miss_pkgs[@]} -eq 0 ]; then
        echo -e "${GREEN}✅ All packages installed.${NC}"
    else
        echo -e "${YELLOW}⚠️  以下包缺失（源里没有或网络失败），请手动补装：${NC}"
        printf '   - %s\n' "${miss_pkgs[@]}"
        echo -e "${CYAN}   sudo dnf install -y ${miss_pkgs[*]}${NC}"
    fi

    # --- 4.1 KDE/Qt 配色读取基石: plasma-integration ---
    # 提供 Qt6 的 KDE plasma 平台主题 (KDEPlasmaPlatformTheme6.so),
    # 让 Dolphin 在内的所有 KDE/Qt 应用读取 ~/.config/kdeglobals 里 [Colors:*] 的配色。
    # 必须 --setopt=install_weak_deps=False, 否则 dnf 默认会连带安装整套
    # plasma-desktop / plasma-workspace / kwin / ibus / vlc (= 整个 KDE)。
    echo -e "${YELLOW}>> Installing plasma-integration (KDE/Qt color scheme bridge)...${NC}"
    x sudo dnf install -y --setopt=install_weak_deps=False plasma-integration

    # --- 4.2 禁掉 xwaylandvideobridge 自启：它是 xdg-desktop-portal-kde 的依赖，
    # 开机即占一个黑窗口（Wayland→X11 推流桥），纯 Wayland 会话用不上；
    # 有 X11 投屏需求时手动起即可（D-Bus 按需也能拉起，不删包）
    echo -e "${CYAN}>> Disabling xwaylandvideobridge autostart (black window on niri)...${NC}"
    mkdir -p "$HOME/.config/autostart"
    if [ -f /etc/xdg/autostart/org.kde.xwaylandvideobridge.desktop ]; then
        cp -f /etc/xdg/autostart/org.kde.xwaylandvideobridge.desktop "$HOME/.config/autostart/" 2>/dev/null
        grep -q "^Hidden=true" "$HOME/.config/autostart/org.kde.xwaylandvideobridge.desktop" 2>/dev/null \
            || echo "Hidden=true" >> "$HOME/.config/autostart/org.kde.xwaylandvideobridge.desktop"
        echo -e "${GREEN}✅ xwaylandvideobridge autostart disabled.${NC}"
    else
        echo -e "${CYAN}>> No videobridge autostart file, skipping.${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"
    
    # --- 5. by-mgr 就绪检查（只检查、不部署；本体由 install.sh 开场第 0 步备好）---
    BY_MGR_BIN="${BY_MGR_BIN:-$HOME/.local/bin/by-mgr}"
    if [ ! -x "$BY_MGR_BIN" ] || ! "$BY_MGR_BIN" --version &>/dev/null; then
        echo -e "${RED}❌ by-mgr 未就绪：$BY_MGR_BIN 不可用，请先通过 install.sh 运行（开场会备好 by-mgr）。${NC}"
        return 1
    fi
    echo -e "${GREEN}✅ by-mgr ready: $BY_MGR_BIN${NC}"

    # --- 6. 配置部署（by-mgr deploy，取代自有 stow 循环）---
    # 旧循环直接 rm -rf 冲突目录、失败也照报成功；现统一走 by-mgr：
    # 冲突进回收站、local 模式先自动快照、逐模块报错、写 deploy.log、
    # 模板同步与配色同步都在 by-mgr 内闭环。
    echo -e "\n${YELLOW}==== Configuration Deployment Mode (by-mgr deploy) ====${NC}"
    echo "  1) ☁️  Sync Latest (Git -> Local) [by-mgr deploy stow]"
    echo "  2) 📁  Local Copy (Restore physical files) [by-mgr deploy local]"
    echo "  0) ⏭️  Skip (Keep current system configs unchanged)"

    # 强制单选循环
    while true; do
        read -p "Select Mode [0/1/2]: " deploy_mode

        case "$deploy_mode" in
            1)
                while true; do
                    echo -e "${YELLOW}>> Deploying configuration via by-mgr deploy stow...${NC}"
                    if BY_MGR_REPO="$REPO_DIR" "$BY_MGR_BIN" deploy stow; then
                        echo -e "${GREEN}✅ Configuration deployment complete!${NC}"
                        break 2
                    fi
                    echo -e "${RED}❌ by-mgr deploy stow failed. See deploy log for details.${NC}"
                    printf "Retry?  r = Repeat deploy (DEFAULT)   e = Exit\n====> "
                    local ans
                    if ! read -r ans; then
                        echo -e "${YELLOW}>> No input (EOF), aborting.${NC}"
                        return 1
                    fi
                    case "$ans" in
                        e|E) echo -e "${RED}>> Aborted by user.${NC}"; return 1 ;;
                        *) ;;
                    esac
                done
                ;;
            2)
                while true; do
                    echo -e "${YELLOW}>> Deploying configuration via by-mgr deploy local...${NC}"
                    if BY_MGR_REPO="$REPO_DIR" "$BY_MGR_BIN" deploy local; then
                        echo -e "${GREEN}✅ Configuration deployment complete!${NC}"
                        break 2
                    fi
                    echo -e "${RED}❌ by-mgr deploy local failed. See deploy log for details.${NC}"
                    printf "Retry?  r = Repeat deploy (DEFAULT)   e = Exit\n====> "
                    local ans
                    if ! read -r ans; then
                        echo -e "${YELLOW}>> No input (EOF), aborting.${NC}"
                        return 1
                    fi
                    case "$ans" in
                        e|E) echo -e "${RED}>> Aborted by user.${NC}"; return 1 ;;
                        *) ;;
                    esac
                done
                ;;
            0)
                # 严格跳过机制：不做任何复制、删除和链接操作
                echo -e "${YELLOW}>> Skipped configuration deployment. No custom files were modified.${NC}"
                break
                ;;
            *)
                # 捕获非法输入
                echo -e "${RED}❌ Invalid selection. Please enter exactly 0, 1, or 2.${NC}"
                ;;
        esac
    done


# --- 7. 自动化色彩与壁纸初始化 ---
        local INIT_SCRIPT="$HOME/.config/niri/scripts/init-wallpaper.sh"
        if [ -f "$INIT_SCRIPT" ]; then
            echo -e "${BLUE}>> Activating visual engine...${NC}"
            chmod +x "$INIT_SCRIPT"
            x bash "$INIT_SCRIPT"
        else
            local ALT_INIT="$DOTFILES_DIR/niri/.config/niri/scripts/init-wallpaper.sh"
            if [ -f "$ALT_INIT" ]; then
                chmod +x "$ALT_INIT"
                x bash "$ALT_INIT"
            fi
        fi


    echo -e "\n${BLUE}-----------------------------------------------------${NC}"


    # --- 8. Shell 环境初始化（PATH 与 Starship 注入）---
    # by-mgr 本体已在第 5 步就绪，已删的 legacy lib 复制也一并去掉了；
    # 这里只做交互式 Shell 的注入。
    echo -e "${BLUE}>> Registering global commands and initializing shell...${NC}"
    local BIN_DIR="$HOME/.local/bin"

    if [ -x "$BIN_DIR/by-mgr" ]; then
        # 定义配置文件路径
        local BASH_RC="$HOME/.bashrc"
        local ZSH_RC="$HOME/.zshrc"
        local BASH_PROFILE="$HOME/.bash_profile"

        # --- A. 注入 PATH 与 Starship (针对交互式 Shell) ---
        for rc in "$BASH_RC" "$ZSH_RC"; do
            if [ -f "$rc" ]; then
                local PATH_LINE="export PATH=\"\$HOME/.local/bin:\$PATH\""
                local STARSHIP_CMD='eval "$(starship init '$(basename "$rc" | sed 's/rc//;s/\.//')')"'

                # 注入 PATH
                if ! grep -Fq "$PATH_LINE" "$rc"; then
                    echo -e "\n# Biyuan CLI Tools & Environment" >> "$rc"
                    echo "$PATH_LINE" >> "$rc"
                fi

                # 注入 Starship
                if ! grep -Fq "starship init" "$rc"; then
                    echo -e "\n# Starship Prompt Initialization" >> "$rc"
                    echo "$STARSHIP_CMD" >> "$rc"
                fi
            fi
        done

        echo -e "${GREEN}✅ Command and Shell environment deployed successfully.${NC}"
    else
        echo -e "${RED}❌ Error: by-mgr binary not found at $BIN_DIR/by-mgr${NC}"
    fi


    # --- 9. 登录管理器部署 ---
    local GREETD_SCRIPT="$REPO_DIR/scripts/07_greetd_setup.sh"
    if [ ! -f "$GREETD_SCRIPT" ]; then
        echo -e "${RED}❌ ERROR: Setup script not found at $GREETD_SCRIPT!${NC}"
        return 1
    fi

    # 检测是否已有其他登录管理器
    local existing_dm=""
    for dm in gdm sddm lightdm greetd plasmalogin; do
        if rpm -q "$dm" &>/dev/null; then
            existing_dm="$dm"
            break
        fi
    done

    if [ -n "$existing_dm" ]; then
        echo -e "${CYAN}>> Detected existing display manager: $existing_dm, skipping greetd.${NC}"
    else
        while true; do
            echo -e "\n${BLUE}==================================================${NC}"
            echo -e "${YELLOW}>> No display manager found. Please select:${NC}"
            echo -e "   ${CYAN}[1]${NC} greetd + tuigreet (Recommended for Niri)"
            echo -e "   ${CYAN}[2]${NC} Skip (No display manager)"
            echo -e "${BLUE}==================================================${NC}"
            read -p "Enter your choice [1-2]: " dm_choice

            case "$dm_choice" in
                1)
                    source "$GREETD_SCRIPT"
                    setup_greetd_niri
                    break
                    ;;
                2)
                    echo -e "${YELLOW}>> Skipped display manager deployment.${NC}"
                    break
                    ;;
                *)
                    echo -e "${RED}❌ Invalid input! Please choose [1-2].${NC}"
                    ;;
            esac
        done
    fi
}
