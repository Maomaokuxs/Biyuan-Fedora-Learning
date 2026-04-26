#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] Snapper 底层防护与配置恢复管理${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. [Snapper 引导配置模块] ---
    # 检查是否安装了 snapper 且是否存在任何配置
    if ! command -v snapper &> /dev/null || [ ! "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> [预检] 尚未检测到 Snapper 配置，准备进行初始化引导...${NC}"
        
        # 确保软件包已安装
        if ! command -v snapper &> /dev/null; then 
            echo -e "正在安装 Snapper 软件包..."
            sudo dnf install -y snapper &> /dev/null
        fi

        # 扫描 Btrfs 挂载点
        echo -e "正在检测可创建快照的 Btrfs 子卷..."
        mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)
        
        if [ ${#subvolumes[@]} -eq 0 ]; then
            echo -e "${RED}!! 未检测到有效的 Btrfs 挂载点，无法建立 Snapper 保护。${NC}"
        else
            echo -e "${BLUE}发现以下可保护的挂载点:${NC}"
            for i in "${!subvolumes[@]}"; do echo "  $((i+1))) ${subvolumes[i]}"; done
            echo "  0) 跳过此步骤"
            
            read -p "请输入要配置的编号 (多选请用空格隔开): " snap_choices
            
            if [[ -n "$snap_choices" && "$snap_choices" != "0" ]]; then
                for idx in $snap_choices; do
                    if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#subvolumes[@]}" ]; then continue; fi
                    
                    local target_vol="${subvolumes[$((idx-1))]}"
                    # 生成配置名：去掉斜杠，如果为空（根目录）则设为 root
                    local config_name=$(echo "$target_vol" | sed 's/\///g')
                    [ -z "$config_name" ] && config_name="root"
                    
                    echo -e "正在为 $target_vol 创建配置 [$config_name]..."
                    sudo snapper -c "$config_name" create-config "$target_vol" && echo -e "${GREEN}✅ $target_vol 配置成功。${NC}"
                done
            fi
        fi
    else
        echo -e "${GREEN}>> [状态] 检测到已有 Snapper 配置，跳过初始化。${NC}"
    fi

    # --- 2. [快照询问模块] ---
    # 只要环境就绪，就询问是否创建快照
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        read -p "🚨 是否在部署前为系统创建一个安全快照？[y/N]: " do_snap
        if [[ $do_snap == [yY] ]]; then
            # 默认使用 root 配置进行快照
            local target_c=$(sudo snapper list-configs | awk 'NR==3 {print $1}')
            [ -z "$target_c" ] && target_c="root"
            
            echo -e "${YELLOW}>> 正在创建快照...${NC}"
            sudo snapper -c "$target_c" create --description "Pre_Deployment_Backup" --userdata "origin=biyuan_wizard"
            echo -e "${GREEN}✅ 快照创建完成！${NC}"
        fi
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. [本地恢复模块] ---
    # 放在快照保护之后，最安全
    if [ -d "$BACKUP_ROOT" ] && [ "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> [配置] 检测到本地历史备份。${NC}"
        read -p "是否从本地备份恢复配置文件？[y/N]: " local_restore
        
        if [[ $local_restore == [yY] ]]; then
            mapfile -t backups < <(ls -dt "$BACKUP_ROOT"/* 2>/dev/null)
            echo -e "\n${BLUE}可用备份列表:${NC}"
            for i in "${!backups[@]}"; do
                echo "  $((i+1))) $(basename "${backups[i]}")"
            done
            read -p "请输入编号 (0跳过): " b_choice
            
            if [[ "$b_choice" -gt 0 ]] && [[ "$b_choice" -le "${#backups[@]}" ]]; then
                selected_path="${backups[$((b_choice-1))]}"
                dir_name=$(basename "$selected_path")
                module_name=$(echo "$dir_name" | rev | cut -d'_' -f1 | rev)

                if [[ "$dir_name" == "$module_name" ]] || [ -z "$module_name" ]; then
                    read -p "识别不到模块名，请输入 (如 niri): " module_name
                fi

                if [ -n "$module_name" ] && [ "$module_name" != "skip" ]; then
                    echo -e "${BLUE}>> 正在同步: $module_name${NC}"
                    repo_path="$DOTFILES_DIR/$module_name"
                    mkdir -p "$repo_path"

                    cp -rf "$selected_path"/. "$repo_path/" 2>/dev/null
                    cd "$DOTFILES_DIR"
                    stow -t ~ --adopt "$module_name" 2>/dev/null
                    cp -rf "$selected_path"/. "$repo_path/" 2>/dev/null
                    
                    echo -e "${GREEN}✅ $module_name 恢复完成。${NC}"
                fi
            fi
        fi
    fi
}