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
    
    mapfile -t all_mounts_raw < <(findmnt -t btrfs -n -o TARGET)
    
    configured_data=$(sudo snapper list-configs 2>/dev/null | awk 'NR>2 {print $1, $NF}')

    display_names=()   
    clean_paths=()     
    status_tags=()     
    config_names=()    

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
    for i in "${!display_names[@]}"; do
        echo -e "  $((i+1))) ${status_tags[i]} ${display_names[i]}"
    done
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

                if [ -n "$conf_n" ]; then
                    echo -e "${CYAN}>> Creating security snapshot for [$raw_n]...${NC}"
                    if sudo snapper -c "$conf_n" create --description "Manual_Pre_Deployment"; then
                        echo -e "${GREEN}✅ [$raw_n] Snapshot completed.${NC}"
                    else
                        echo -e "${RED}❌ [$raw_n] Snapshot failed!${NC}"
                    fi
                else
                    echo -e "${YELLOW}>> Initializing subvolume [$raw_n]...${NC}"
                    output=$(sudo snapper -c "$target_conf" create-config "$path_n" 2>&1)
                    
                    if [ $? -eq 0 ]; then
                        # Granting user permissions and taking first snapshot
                        sudo sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"$(whoami)\"/" "/etc/snapper/configs/$target_conf"
                        sudo snapper -c "$target_conf" create --description "Initial_Snapshot"
                        echo -e "${GREEN}✅ [$raw_n] Initialization & Initial Snapshot successful.${NC}"
                    else
                        # Handling specific Snapper error codes/messages
                        if echo "$output" | grep -q "subvolume already covered"; then
                            echo -e "${BLUE}ℹ️  [$raw_n] Already covered by parent subvolume; area secure. Skipping...${NC}"
                        elif echo "$output" | grep -q "already exists"; then
                            echo -e "${YELLOW}⚠️  Config exists but not cached. Attempting forced snapshot...${NC}"
                            sudo snapper -c "$target_conf" create --description "Forced_Snapshot" && \
                            echo -e "${GREEN}✅ [$raw_n] Forced snapshot successful!${NC}" || \
                            echo -e "${RED}❌ Forced snapshot failed!${NC}"
                        else
                            echo -e "${RED}❌ Failed to process [$raw_n]: $output${NC}"
                        fi
                    fi
                fi
            fi
        done
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

# --- 4. 时间轴全量静默备份 (优化与修复版) ---

    local BACKUP_ROOT="$HOME/.dotfiles_backup"
    local date_tag=$(date +%Y%m%d_%H%M%S)
    local current_backup_dir="$BACKUP_ROOT/$date_tag"
    
    echo -e "${BLUE}>> Performing silent physical backup of local configs...${NC}"
    if [ -d "$DOTFILES_DIR" ]; then
        local backed_any=false
        mkdir -p "$current_backup_dir"
        
        for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
            # 1. 动态确定目标路径 (适配非 .config 目录)
            local src="$HOME/.config/$module"
            [[ "$module" == "colors" ]] && src="$HOME/.cache/hellwal"
            [[ "$module" == "bash" ]] && src="$HOME/.bashrc"
            
            if [ -e "$src" ]; then
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
                cp -aL "$src" "$dest"
                backed_any=true
            fi
        done
        
        if [ "$backed_any" = true ]; then
             echo -e "${GREEN}✅ Physical files extracted and backed up to: $current_backup_dir${NC}"
        else
             # 如果全是空文件夹或都不存在，销毁这次的备份日期目录
             rm -rf "$current_backup_dir"
             echo -e "${YELLOW}>> No local configurations needed backup.${NC}"
        fi
    fi
}
