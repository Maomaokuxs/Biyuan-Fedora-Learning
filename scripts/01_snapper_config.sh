#!/bin/bash
# 文件位置: scripts/01_snapper_config.sh

setup_snapper_and_backup() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] 磁盘防护初始化与时间轴备份${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    sudo -v || { echo -e "${RED}❌ 无法获取管理员权限，脚本退出。${NC}"; exit 1; }

    # --- 1. 环境预检 ---
    if ! command -v snapper &> /dev/null; then
        echo -e "${YELLOW}>> 未检测到 snapper，正在为您安装基础防护组件...${NC}"
        sudo dnf install -y snapper
    fi

    echo -e "${BLUE}>> 正在分析磁盘 Btrfs 拓扑与快照配置...${NC}"
    
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
            status_tags+=("${GREEN}[已配置]${NC}")
            config_names+=("$conf")
        else
            status_tags+=("${YELLOW}[未初始化]${NC}")
            config_names+=("")
        fi
    done

    # --- 2. 统一交互菜单 ---
    echo -e "\n${YELLOW}>> 发现以下可快照子卷，请选择要备份/初始化的编号：${NC}"
    for i in "${!display_names[@]}"; do
        echo -e "  $((i+1))) ${status_tags[i]} ${display_names[i]}"
    done
    echo "  a) 全部执行 (一键配置并快照)"
    echo "  0) ⏭️ 跳过"
    
    read -p "选择编号 [支持多选, 如 1 2 或 a]: " choices
    
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
                    echo -e "${CYAN}>> 正在为 [$raw_n] 创建安全快照...${NC}"
                    if sudo snapper -c "$conf_n" create --description "Manual_Pre_Deployment"; then
                        echo -e "${GREEN}✅ [$raw_n] 快照完成。${NC}"
                    else
                        echo -e "${RED}❌ [$raw_n] 快照创建失败！${NC}"
                    fi
                else
                    echo -e "${YELLOW}>> 正在尝试初始化子卷 [$raw_n] ...${NC}"
                    output=$(sudo snapper -c "$target_conf" create-config "$path_n" 2>&1)
                    
                    if [ $? -eq 0 ]; then
                        sudo sed -i "s/ALLOW_USERS=\"\"/ALLOW_USERS=\"$(whoami)\"/" "/etc/snapper/configs/$target_conf"
                        sudo snapper -c "$target_conf" create --description "Initial_Snapshot"
                        echo -e "${GREEN}✅ [$raw_n] 初始化并快照成功。${NC}"
                    else
                        if echo "$output" | grep -q "subvolume already covered"; then
                            echo -e "${BLUE}ℹ️  [$raw_n] 已被父级包含覆盖，该区域已安全，无需独立快照。${NC}"
                        elif echo "$output" | grep -q "already exists"; then
                            echo -e "${YELLOW}⚠️  配置文件已存在但未被系统缓存，尝试直接打快照...${NC}"
                            sudo snapper -c "$target_conf" create --description "Forced_Snapshot" && echo -e "${GREEN}✅ [$raw_n] 强制快照成功！${NC}" || echo -e "${RED}❌ 快照失败！${NC}"
                        else
                            echo -e "${RED}❌ 无法处理 [$raw_n]: $output${NC}"
                        fi
                    fi
                fi
            fi
        done
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 4. 时间轴全量静默备份 (核心修复) ---
    local BACKUP_ROOT="$HOME/.dotfiles_backup"
    local date_tag=$(date +%Y%m%d_%H%M%S)
    local current_backup_dir="$BACKUP_ROOT/$date_tag"
    
    echo -e "${BLUE}>> 正在静默执行本地配置物理备份 (解引用软链接)...${NC}"
    if [ -d "$DOTFILES_DIR" ]; then
        local backed_any=false
        mkdir -p "$current_backup_dir"
        
        for module in $(ls "$DOTFILES_DIR" 2>/dev/null); do
            local src="$HOME/.config/$module"
            [[ "$module" == "colors" ]] && src="$HOME/.cache/hellwal"
            
            # 使用 -e 检查文件或目录是否存在（即使是软链接也能正确判断）
            if [ -e "$src" ]; then
                local dest="$current_backup_dir/$module"
                local rel=$(dirname "$src" | sed "s|$HOME||")
                mkdir -p "$dest$rel"
                
                # 【关键修复】：加入了 -L 参数，强制解析软链接，提取真实物理文件
                cp -rLf "$src" "$dest$rel/"
                backed_any=true
            fi
        done
        
        if [ "$backed_any" = true ]; then
             echo -e "${GREEN}✅ 真实物理文件已安全抽离并备份至: $current_backup_dir${NC}"
        else
             rm -rf "$current_backup_dir"
             echo -e "${YELLOW}>> 未检测到需要备份的本地配置。${NC}"
        fi
    fi
}