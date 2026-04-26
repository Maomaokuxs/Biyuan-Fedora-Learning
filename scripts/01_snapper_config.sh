#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] Snapper 保护与本地备份恢复${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. [核心：本地备份恢复逻辑] ---
    # 无论 Snapper 是否配置，都必须先检查此项
    if [ -d "$BACKUP_ROOT" ] && [ "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> 检测到本地备份目录: $BACKUP_ROOT${NC}"
        read -p "🚨 是否需要从本地备份恢复某个配置文件？[y/N]: " local_restore
        
        if [[ $local_restore == [yY] ]]; then
            echo -e "\n${BLUE}可用备份列表 (按时间排序):${NC}"
            mapfile -t backups < <(ls -dt "$BACKUP_ROOT"/*)
            
            for i in "${!backups[@]}"; do
                echo "  $((i+1))) $(basename "${backups[i]}")"
            done
            echo "  0) 跳过恢复"

            read -p "请选择编号 (1-${#backups[@]}): " b_choice
            
            if [[ "$b_choice" -gt 0 ]] && [[ "$b_choice" -le "${#backups[@]}" ]]; then
                selected_path="${backups[$((b_choice-1))]}"
                dir_name=$(basename "$selected_path")
                
                # 智能提取模块名 (例如从 20260425_221154_niri 提取 niri)
                module_name=$(echo "$dir_name" | cut -d'_' -f3-)
                
                # 安全阀：如果目录名不符合命名规范，要求手动输入
                if [ -z "$module_name" ]; then
                    echo -e "${RED}无法自动识别该备份的模块名。${NC}"
                    read -p "请输入对应的模块名 (如: niri, starship, bash, kitty): " module_name
                fi

                if [ -n "$module_name" ]; then
                    repo_module_path="$DOTFILES_DIR/$module_name"
                    
                    echo -e "${YELLOW}>> 正在精准恢复 $module_name 模块内容至仓库...${NC}"
                    
                    # 确保仓库目录存在
                    mkdir -p "$repo_module_path"
                    
                    # 物理恢复内容到仓库 (使用 /. 确保拷贝目录下所有内容)
                    if [ -d "$selected_path" ]; then
                        cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null
                    else
                        cp -f "$selected_path" "$repo_module_path" 2>/dev/null
                    fi

                    # --- 核心改进：使用 --restow 进行无损链接重连 ---
                    echo -e "${BLUE}>> 正在重新同步链接 (Restow)...${NC}"
                    cd "$DOTFILES_DIR"
                    # -R 代表 --restow，会断开旧链接并重新建立，不影响其他模块
                    stow -R -v -t ~ "$module_name" 2>/dev/null
                    
                    echo -e "${GREEN}✅ $module_name 恢复完成，其他链接（如 Kitty）已安全保留。${NC}\n"
                else
                    echo -e "${RED}未提供有效模块名，已取消恢复。${NC}"
                fi
            fi
        fi
    fi

    # --- 2. [核心：Snapper 状态检测] ---
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> Snapper 配置已激活。${NC}"
        echo -e "${GREEN}>> ✅ Snapper 环境就绪，进入下一阶段。${NC}\n"
    else
        # 初始安装
        if ! command -v snapper &> /dev/null; then 
            echo -e "${YELLOW}>> 正在补充安装 Snapper...${NC}"
            sudo dnf install -y snapper
        fi

        echo -e "正在检测可创建快照的 Btrfs 子卷..."
        mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)
        
        if [ ${#subvolumes[@]} -eq 0 ]; then
            echo -e "${RED}未检测到 Btrfs 挂载点，跳过 Snapper 配置。${NC}\n"
        else
            echo -e "发现以下挂载点:"
            for i in "${!subvolumes[@]}"; do echo "  $((i+1))) ${subvolumes[i]}"; done
            echo "  0) 跳过此步骤"
            
            read -p "请输入选项 (多选空格隔开): " choices
            [[ -z "$choices" || "$choices" == "0" ]] && return

            for idx in $choices; do
                if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#subvolumes[@]}" ]; then continue; fi
                local sub_display="${subvolumes[$((idx-1))]}"
                local clean_sub=$(echo "$sub_display" | sed 's/[^/]*//')
                local config_name=$(echo "$clean_sub" | sed 's/\///g')
                [ -z "$config_name" ] && config_name="root"
                
                sudo snapper -c "$config_name" create-config "$clean_sub" && echo -e "${GREEN}✅ $sub_display 配置完成。${NC}"
            done
        fi
    fi
}