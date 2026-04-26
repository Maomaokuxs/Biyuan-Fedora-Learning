#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] Snapper 底层防护与颜色/配置恢复管理${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. Snapper 引导与快照创建 ---
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${GREEN}>> [状态] Snapper 底层快照配置已激活。${NC}"
        read -p "🚨 是否在部署前为当前系统创建一个安全快照？[y/N]: " do_snap
        if [[ $do_snap == [yY] ]]; then
            local target_c=$(sudo snapper list-configs | awk 'NR==3 {print $1}')
            [ -z "$target_c" ] && target_c="root"
            echo -e "${YELLOW}>> 正在创建快照...${NC}"
            sudo snapper -c "$target_c" create --description "Pre_Deployment_Backup"
            echo -e "${GREEN}✅ 快照创建完成！${NC}"
        fi
    else
        echo -e "${YELLOW}>> [提示] 尚未检测到 Snapper 配置，准备进行初始化...${NC}"
        if ! command -v snapper &> /dev/null; then sudo dnf install -y snapper &> /dev/null; fi

        mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)
        if [ ${#subvolumes[@]} -gt 0 ]; then
            echo -e "发现以下挂载点:"
            for i in "${!subvolumes[@]}"; do echo "  $((i+1))) ${subvolumes[i]}"; done
            read -p "请选择要保护的编号 (多选空格隔开): " snap_choices
            if [[ -n "$snap_choices" && "$snap_choices" != "0" ]]; then
                for idx in $snap_choices; do
                    [ "$idx" -lt 1 ] || [ "$idx" -gt "${#subvolumes[@]}" ] && continue
                    local target_vol="${subvolumes[$((idx-1))]}"
                    local config_name=$(echo "$target_vol" | sed 's/\///g')
                    [ -z "$config_name" ] && config_name="root"
                    sudo snapper -c "$config_name" create-config "$target_vol"
                done
                echo -e "${GREEN}✅ Snapper 配置已建立。${NC}"
            fi
        fi
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 2. 颜色缓存与 Dotfiles 恢复模块 ---
    local B_PATH="$HOME/.dotfiles_backup"
    if [ -d "$B_PATH" ] && [ "$(ls -A "$B_PATH" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> [配置] 检测到本地历史备份。${NC}"
        read -p "是否从本地备份恢复配置文件（含颜色系统）？[y/N]: " local_restore
        
        if [[ $local_restore == [yY] ]]; then
            mapfile -t backups < <(ls -dt "$B_PATH"/* 2>/dev/null)
            echo -e "\n${BLUE}可用备份列表:${NC}"
            for i in "${!backups[@]}"; do
                echo "  $((i+1))) $(basename "${backups[i]}")"
            done
            read -p "请输入要恢复的编号 (多选空格隔开, 0跳过): " b_choices
            
            for b_idx in $b_choices; do
                [[ "$b_idx" == "0" ]] && break
                selected_path="${backups[$((b_idx-1))]}"
                dir_name=$(basename "$selected_path")
                # 提取模块名 (2026_niri -> niri)
                module_name=$(echo "$dir_name" | rev | cut -d'_' -f1 | rev)

                if [[ "$dir_name" == "$module_name" ]]; then
                    read -p "无法识别备份 [$dir_name] 的模块名，请输入 (如 colors, niri): " module_name
                fi

                if [ -n "$module_name" ] && [ "$module_name" != "skip" ]; then
                    echo -e "${BLUE}>> 正在同步模块: $module_name${NC}"
                    repo_module_path="$DOTFILES_DIR/$module_name"
                    mkdir -p "$repo_module_path"

                    # 核心逻辑：物理拷贝内容到仓库
                    cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null

                    # --- 特殊路径判定 ---
                    # 默认 stow 是基于家目录 (~) 的。
                    # 如果模块里包含 .cache 结构，stow 会自动在 ~/.cache 下创建链接
                    cd "$DOTFILES_DIR"
                    
                    # 使用 --adopt 采纳家目录现有文件（特别是 .cache/hellwal）
                    # 如果目录不存在，先创建父目录防止 stow 报错
                    [ "$module_name" == "colors" ] && mkdir -p "$HOME/.cache"
                    
                    stow -t ~ --adopt "$module_name" 2>/dev/null
                    
                    # 二次同步仓库，确保备份版本覆盖家目录被吸纳的版本
                    cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null
                    echo -e "${GREEN}✅ $module_name 恢复并建立链接。${NC}"
                fi
            done
        fi
    fi
}