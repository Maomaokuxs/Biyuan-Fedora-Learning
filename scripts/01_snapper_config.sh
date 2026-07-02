#!/bin/bash
# 文件位置: scripts/01_snapper_config.sh

setup_snapper_and_backup() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [Phase 1] Disk Protection & Config Backup${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    sudo -v || { echo -e "${RED}Failed to obtain sudo privileges. Exiting...${NC}"; exit 1; }

    # --- 1. 环境预检 ---

    # 检测是否有配置snpper，如果配置了就会提示用户进行快照，并且弹出能够进行快照的挂载点
    
    if ! command -v snapper &> /dev/null; then
        echo -e "${YELLOW}>> Snapper not found. Installing protection components...${NC}"
        sudo dnf install -y snapper
    fi

    echo -e "${BLUE}>> Analyzing Btrfs topology & snapshot status...${NC}"
    # 使用 findmnt 找出所有 Btrfs 格式的挂载点
    mapfile -t all_mounts_raw < <(findmnt -t btrfs -n -o TARGET)
    # 使用 awk 处理 snapper list-configs 的输出，识别哪些挂载点已经配置了快照功能。
    configured_data=$(sudo snapper list-configs 2>/dev/null | awk 'NR>2 {print $1, $NF}')

    display_names=()   
    clean_paths=()     
    status_tags=()     
    config_names=()    
    # 将结果存入数组 display_names（显示名）和 status_tags（状态标签：是 active 还是 inactive）
    for raw in "${all_mounts_raw[@]}"; do
        clean=$(echo "$raw" | grep -o '/.*')
        conf=$(echo "$configured_data" | awk -v m="$clean" '$2==m {print $1}')
        
        display_names+=("$raw")
        clean_paths+=("$clean")
        
        if [ -n "$conf" ]; then
            status_tags+=("${GREEN}[active]${NC}")
            config_names+=("$conf")
        else
            status_tags+=("${YELLOW}[inactive]${NC}")
            config_names+=("")
        fi
    done

    # --- 2. 统一交互菜单 ---

    echo -e "\n${YELLOW}>> Found subvolumes. Select IDs to initialize/backup:${NC}"
    # 列出所有发现的子卷（Subvolumes），并用颜色标记它们当前的保护状态
    for i in "${!display_names[@]}"; do
        echo -e "  $((i+1))) ${display_names[i]} ${status_tags[i]}"
    done
    # 支持全选与跳过
    echo "  a) All (Batch setup & snapshot)"
    echo "  0) Skip"
    
    read -p "Selection [Supports multiple, e.g., 1 2 or a]: " choices
    
    if [[ "$choices" != "0" && -n "$choices" ]]; then
        [[ "$choices" == "a" ]] && choices=$(seq 1 ${#display_names[@]})

    # --- 3. 结果导向的执行循环 ---

        for idx in $choices; do
            if [[ "$idx" -gt 0 ]] && [[ "$idx" -le "${#display_names[@]}" ]]; then
                i=$((idx-1))
                local raw_n="${display_names[i]}"
                local path_n="${clean_paths[i]}"
                local conf_n="${config_names[i]}"

                local target_conf="root"
                [ "$path_n" != "/" ] && target_conf=$(echo "$path_n" | sed 's|^/||' | sed 's|/|-|g')
                # 创建对应挂载点快照，如果没有配置文件将以挂载点为名称创建配置文件
                if [ -n "$conf_n" ]; then
                    echo -e "${CYAN}>> Creating security snapshot for [$raw_n]...${NC}"
                    if sudo snapper -c "$conf_n" crea\te --description "Manual_Pre_Deployment"; then
                        echo -e "${GREEN}✅ [$raw_n] Snapshot completed.${NC}"
                    else
                        echo -e "${RED}❌ [$raw_n] Snapshot failed!${NC}"
                    fi
                else
                    echo -e "${YELLOW}>> Initializing subvolume [$raw_n]...${NC}"
                    output=$(sudo snapper -c "$target_conf" create-config "$path_n" 2>&1)
                    
                    if [ $? -eq 0 ]; then
                        # 自动修改 /etc/snapper/configs/ 下的文件，允许当前普通用户操作快照，无需每次都输入，并且生成快照
                        sudo sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"$(whoami)\"/" "/etc/snapper/configs/$target_conf"
                        sudo snapper -c "$target_conf" create --description "Initial_Snapshot"
                        echo -e "${GREEN}✅ [$raw_n] Initialization & Initial Snapshot successful.${NC}"
                    else
                        # 处理snapper提供的报错信息
                        # subvolume already covered (所选子卷已覆盖在配置文件中)
                        if echo "$output" | grep -q "subvolume already covered"; then
                            echo -e "${BLUE}ℹ️  [$raw_n] Already covered by parent subvolume; area secure. Skipping...${NC}"
                        # already exists (配置冲突)
                        elif echo "$output" | grep -q "already exists"; then
                            echo -e "${YELLOW}⚠️  Config exists but not cached. Attempting forced snapshot...${NC}"
                            sudo snapper -c "$target_conf" create --description "Forced_Snapshot" && \
                            echo -e "${GREEN}✅ [$raw_n] Forced snapshot successful!${NC}" || \
                            echo -e "${RED}❌ Forced snapshot failed!${NC}"
                        # 其他未知错误
                        else
                            echo -e "${RED}❌ Failed to process [$raw_n]: $output${NC}"
                        fi
                    fi
                fi
            fi
        done
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

# --- 4. 按时间全量静默备份物理文件 ---

    local BACKUP_ROOT="$HOME/.config/by-mgr/backup"
    local date_tag=$(date +%Y%m%d_%H%M%S)
    local current_backup_dir="$BACKUP_ROOT/$date_tag"
    
    echo -e "${BLUE}>> Performing silent physical backup of local configs...${NC}"
    # 创建备份文件夹
    if [ -d "$DOTFILES_DIR" ]; then
        local backed_any=false
        mkdir -p "$current_backup_dir"
        # 遍历 $DOTFILES_DIR 目录
        for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
            # 1. 默认探测路径（目录优先）
            local src="$HOME/.config/$module"
            
            # 2. 特殊路径映射
            [[ "$module" == "bash" ]] && src="$HOME/.bashrc"
            
            # 3. 智能探测：如果默认目录不存在，尝试探测同名文件
            # 这样不仅解决了 starship.toml，以后如果你有 nvim.lua 或 gitconfig 也能自动识别
            if [ ! -e "$src" ] && [ ! -L "$src" ]; then
                # 尝试寻找 .config/ 下的同名 .toml, .conf 或无后缀文件
                if [ -f "$HOME/.config/${module}.toml" ]; then
                    src="$HOME/.config/${module}.toml"
                elif [ -f "$HOME/.config/${module}.conf" ]; then
                    src="$HOME/.config/${module}.conf"
                fi
            fi

            # 4. 终极判断：只要是 存在(e) 或者是 链接(L) 就执行备份
            # [ -L ] 即使链接断了也能抓到它，配合 cp -aL 会很有用
            if [ -e "$src" ] || [ -L "$src" ]; then
                # ... 拦截空目录逻辑 ...
                # ... 执行备份逻辑 ...
                # 【核心修复 1】：拦截空文件夹！如果是个空壳目录，直接跳过，不制造垃圾备份
                if [ -d "$src" ] && [ -z "$(ls -A "$src" 2>/dev/null)" ]; then
                    continue
                fi
                
                # 2. 还原相对于 HOME 的真实目录结构 (例如: .config/hypr 或 .bashrc)
                local rel_path="${src#$HOME/}"
                local dest="$current_backup_dir/$rel_path"
                
                # 【核心修复 2】：优雅创建父级目录，避免错误的嵌套
                mkdir -p "$(dirname "$dest")"
                
                # 【核心修复 3】：使用 -aL (归档模式 + 物理化软链接) 替代 -rLf，更安全地保留权限
                if cp -aL "$src" "$dest"; then
                    # === 新增：实时输出备份成功的项 ===
                    echo -e "   ${CYAN}󰁯  Backed up:${NC} $rel_path"
                    backed_any=true
                fi
            fi
        done
        
        if [ "$backed_any" = true ]; then
             echo -e "\n${GREEN}✅ All physical files extracted to: $current_backup_dir${NC}"
        else
             # 如果全是空文件夹或都不存在，销毁这次的备份日期目录
             rm -rf "$current_backup_dir"
             echo -e "${YELLOW}>> No local configurations needed backup.${NC}"
        fi
    fi
}
