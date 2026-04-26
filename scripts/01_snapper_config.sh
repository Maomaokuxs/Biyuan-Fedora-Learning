#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] 系统底层保护与配置恢复检测${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    # --- 1. 本地备份恢复提醒 (核心新增) ---
    if [ -d "$BACKUP_ROOT" ]; then
        echo -e "${YELLOW}>> 检测到本地备份目录: $BACKUP_ROOT${NC}"
        read -p "🚨 是否需要从本地备份中恢复之前的配置文件？[y/N]: " local_restore
        if [[ $local_restore == [yY] ]]; then
            echo -e "\n${BLUE}最近的本地备份记录 (按时间排序):${NC}"
            ls -dt "$BACKUP_ROOT"/* | head -n 10
            
            echo -e "\n${YELLOW}恢复方法：cp -rf \"$BACKUP_ROOT/目录名/*\" ~/.config/对应目录/${NC}"
            read -p "是否现在打开备份文件夹进行查看？[y/N]: " open_dir
            if [[ $open_dir == [yY] ]]; then
                # 尝试用 dolphin 打开，如果没装就直接 ls
                if command -v dolphin &> /dev/null; then
                    dolphin "$BACKUP_ROOT" &
                else
                    ls -R "$BACKUP_ROOT" | less
                fi
                echo -e "${RED}请手动完成恢复后，回来按回车继续脚本。${NC}"
                read -p "等待中..."
            fi
        fi
    fi

    # --- 2. Snapper 状态检测与快照回滚 ---
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "\n${YELLOW}>> 检测到 Snapper 配置已就绪。${NC}"
        read -p "🚨 是否需要通过 Snapper 快照回滚系统或文件？[y/N]: " snap_restore
        if [[ $snap_restore == [yY] ]]; then
            echo -e "${BLUE}正在列出最近 10 条快照...${NC}"
            sudo snapper -c root list | tail -n 11
            echo -e "${YELLOW}回滚参考: sudo snapper -c root undochange <ID1>..<ID2> /路径${NC}"
            read -p "按回车继续脚本 (如需手动操作请 Ctrl+C)..."
        fi

        echo -e "${GREEN}>> ✅ 状态检测完毕，直接进入下一阶段。${NC}\n"
        return
    fi

    # --- 3. 初始配置逻辑 (若未配置过 Snapper) ---
    if ! command -v snapper &> /dev/null; then sudo dnf install -y snapper; fi
    # ... (后续 findmnt 逻辑保持不变)
}
    # --- 3. [恢复逻辑] 本地备份恢复 (非破坏性) ---
    local B_PATH="$HOME/.dotfiles_backup"
    if [ -d "$B_PATH" ] && [ "$(ls -A "$B_PATH" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> [配置] 检测到本地历史备份记录。${NC}"
        read -p "是否需要从本地备份恢复特定的配置文件？[y/N]: " local_restore
        
        if [[ $local_restore == [yY] ]]; then
            mapfile -t backups < <(ls -dt "$B_PATH"/* 2>/dev/null)
            echo -e "\n${BLUE}可用备份列表:${NC}"
            for i in "${!backups[@]}"; do
                echo "  $((i+1))) $(basename "${backups[i]}")"
            done
            read -p "请输入要恢复的编号 (0跳过): " b_choice
            
            if [[ "$b_choice" -gt 0 ]] && [[ "$b_choice" -le "${#backups[@]}" ]]; then
                selected_path="${backups[$((b_choice-1))]}"
                dir_name=$(basename "$selected_path")
                module_name=$(echo "$dir_name" | rev | cut -d'_' -f1 | rev)

                if [[ "$dir_name" == "$module_name" ]] || [ -z "$module_name" ]; then
                    read -p "无法识别模块名，请输入 (如 niri): " module_name
                fi

                if [ -n "$module_name" ] && [ "$module_name" != "skip" ]; then
                    echo -e "${BLUE}>> 正在精准恢复模块: $module_name${NC}"
                    repo_path="$REPO_DIR/dotfiles/$module_name"
                    mkdir -p "$repo_path"

                    # 物理拷贝 -> stow --adopt 采纳 -> 再次覆盖同步
                    cp -rf "$selected_path"/. "$repo_path/" 2>/dev/null
                    cd "$REPO_DIR/dotfiles"
                    stow -t ~ --adopt "$module_name" 2>/dev/null
                    cp -rf "$selected_path"/. "$repo_path/" 2>/dev/null
                    
                    echo -e "${GREEN}✅ $module_name 配置恢复完成。${NC}"
                fi
            fi
        fi
    fi
    echo -e "\n"
}