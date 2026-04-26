#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] Snapper 底层防护与颜色/配置恢复管理${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. Snapper 引导配置 ---
    if ! command -v snapper &> /dev/null || [ ! "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> 尚未检测到 Snapper 配置，准备进行引导...${NC}"
        if ! command -v snapper &> /dev/null; then sudo dnf install -y snapper &> /dev/null; fi

        mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)
        if [ ${#subvolumes[@]} -gt 0 ]; then
            echo -e "发现 Btrfs 挂载点:"
            for i in "${!subvolumes[@]}"; do echo "  $((i+1))) ${subvolumes[i]}"; done
            read -p "请选择配置编号 (多选空格, 0跳过): " snap_choices
            if [[ -n "$snap_choices" && "$snap_choices" != "0" ]]; then
                for idx in $snap_choices; do
                    [ "$idx" -lt 1 ] || [ "$idx" -gt "${#subvolumes[@]}" ] && continue
                    local target_vol="${subvolumes[$((idx-1))]}"
                    local config_name=$(echo "$target_vol" | sed 's/\///g')
                    [ -z "$config_name" ] && config_name="root"
                    sudo snapper -c "$config_name" create-config "$target_vol"
                done
            fi
        fi
    fi

    # --- 2. 询问创建快照 (环境就绪后) ---
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${GREEN}>> Snapper 环境就绪。${NC}"
        read -p "🚨 是否在部署前立即创建一个安全快照？[y/N]: " do_snap
        if [[ $do_snap == [yY] ]]; then
            local target_c=$(sudo snapper list-configs | awk 'NR==3 {print $1}')
            [ -z "$target_c" ] && target_c="root"
            sudo snapper -c "$target_c" create --description "Pre_Deployment_Backup"
            echo -e "${GREEN}✅ 系统快照已创建。${NC}"
        fi
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. 颜色缓存与 Dotfiles 模块恢复 ---
    if [ -d "$BACKUP_ROOT" ] && [ "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> 检测到本地历史备份。${NC}"
        read -p "是否从备份恢复配置（含 Hellwal 颜色系统）？[y/N]: " local_restore
        
        if [[ $local_restore == [yY] ]]; then
            mapfile -t backups < <(ls -dt "$BACKUP_ROOT"/* 2>/dev/null)
            echo -e "\n${BLUE}可用备份列表:${NC}"
            for i in "${!backups[@]}"; do echo "  $((i+1))) $(basename "${backups[i]}")"; done
            read -p "选择编号 (多选空格): " b_choices
            
            for b_idx in $b_choices; do
                selected_path="${backups[$((b_idx-1))]}"
                dir_name=$(basename "$selected_path")
                module_name=$(echo "$dir_name" | rev | cut -d'_' -f1 | rev)

                if [ -n "$module_name" ] && [ "$module_name" != "skip" ]; then
                    echo -e "${BLUE}>> 正在同步并链接模块: $module_name${NC}"
                    repo_module_path="$DOTFILES_DIR/$module_name"
                    mkdir -p "$repo_module_path"

                    # 物理同步内容
                    cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null

                    # 特殊处理颜色模块的父目录
                    if [ "$module_name" == "colors" ]; then mkdir -p "$HOME/.cache"; fi

                    # Stow 链接
                    cd "$DOTFILES_DIR"
                    stow -t ~ --adopt "$module_name" 2>/dev/null
                    # 二次覆盖，确保仓库版本优先
                    cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null
                fi
            done
            echo -e "${GREEN}✅ 配置恢复任务完成。${NC}"
        fi
    fi
}