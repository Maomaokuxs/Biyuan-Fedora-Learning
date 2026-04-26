#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] 配置恢复管理与 Snapper 检测${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 模块 A：配置文件恢复管理 ---
    if [ -d "$BACKUP_ROOT" ] && [ "$(ls -A "$BACKUP_ROOT" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> 检测到本地存在历史备份记录。${NC}"
        echo -e "你可以选择：[1] 恢复特定模块 [2] 恢复所有模块 [0] 跳过"
        read -p "请输入选项: " recover_choice

        if [[ "$recover_choice" == "1" || "$recover_choice" == "2" ]]; then
            mapfile -t backups < <(ls -dt "$BACKUP_ROOT"/*)
            
            # 如果是恢复特定模块，先列出清单
            if [[ "$recover_choice" == "1" ]]; then
                echo -e "\n${BLUE}可用备份清单:${NC}"
                for i in "${!backups[@]}"; do
                    echo "  $((i+1))) $(basename "${backups[i]}")"
                done
                read -p "请输入要恢复的编号 (空格分隔多选): " b_choices
            else
                # 恢复所有：自动选中所有最新备份
                b_choices=$(seq 1 ${#backups[@]})
            fi

            for idx in $b_choices; do
                if [[ "$idx" -lt 1 ]] || [[ "$idx" -gt "${#backups[@]}" ]]; then continue; fi
                
                selected_path="${backups[$((idx-1))]}"
                dir_name=$(basename "$selected_path")
                module_name=$(echo "$dir_name" | cut -d'_' -f3-)

                # 识别失败时的手动干预
                if [ -z "$module_name" ]; then
                    echo -e "${RED}无法识别备份 [$dir_name] 的模块名。${NC}"
                    read -p "请输入对应的模块名 (或输入 skip 跳过): " module_name
                    [[ "$module_name" == "skip" ]] && continue
                fi

                echo -e "${BLUE}>> 正在同步模块: $module_name${NC}"
                
                # --- 核心逻辑：非破坏性同步 ---
                # 1. 将备份内容同步到仓库，不删除仓库原有结构
                repo_module_path="$DOTFILES_DIR/$module_name"
                mkdir -p "$repo_module_path"
                cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null

                # 2. 安全链接：使用 stow --adopt
                # --adopt 的神奇之处在于：如果家目录有物理文件，它会把物理文件“吸”进仓库作为链接目标
                # 配合我们刚 cp 进去的备份文件，它能强制建立链接而不报错，也不需要 rm -rf
                cd "$DOTFILES_DIR"
                stow -t ~ --adopt "$module_name" 2>/dev/null
                
                # 3. 再次重置仓库状态，确保仓库内是备份的版本而不是刚才被“吸”进来的旧版
                cp -rf "$selected_path"/. "$repo_module_path/" 2>/dev/null
                
                echo -e "${GREEN}✅ 模块 $module_name 已重新链接并恢复完成。${NC}"
            done
            echo -e "${GREEN}>> 恢复流程结束，未触及其他无关配置。${NC}\n"
        fi
    fi

    # --- 模块 B：Snapper 状态检测 ---
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> Snapper 配置已激活。${NC}"
        echo -e "${GREEN}>> ✅ 已就绪。${NC}\n"
    else
        # ... (Snapper 初始化的 Btrfs 检测逻辑，此处保持不变)
        if ! command -v snapper &> /dev/null; then sudo dnf install -y snapper; fi
        # [保留你原来的 findmnt 循环逻辑]
    fi
}