#!/bin/bash

setup_snapper() {
    # 强制局部变量防止丢失
    local B_PATH="$HOME/.dotfiles_backup"

    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [阶段 1] 配置恢复 (非破坏性模式)${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    if [ -d "$B_PATH" ] && [ "$(ls -A "$B_PATH" 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> 检测到本地历史备份。${NC}"
        echo -e "选项: [1] 选择模块恢复 [2] 全部恢复 [0] 跳过"
        read -p "选择: " r_choice

        if [[ "$r_choice" == "1" || "$r_choice" == "2" ]]; then
            mapfile -t backups < <(ls -dt "$B_PATH"/* 2>/dev/null)
            
            if [[ "$r_choice" == "1" ]]; then
                echo -e "\n${BLUE}备份清单:${NC}"
                for i in "${!backups[@]}"; do
                    echo "  $((i+1))) $(basename "${backups[i]}")"
                done
                read -p "输入编号 (空格多选): " b_idxs
            else
                b_idxs=$(seq 1 ${#backups[@]})
            fi

            for idx in $b_idxs; do
                [ -z "$idx" ] && continue
                selected_path="${backups[$((idx-1))]}"
                dir_name=$(basename "$selected_path")
                
                # 增强型模块名提取：取最后一个下划线后的内容
                module_name=$(echo "$dir_name" | rev | cut -d'_' -f1 | rev)

                # 手动校验
                if [[ "$dir_name" == "$module_name" ]] || [ -z "$module_name" ]; then
                    read -p "无法识别备份 [$dir_name] 的模块名，请输入 (如 starship): " module_name
                fi

                if [ -n "$module_name" ]; then
                    echo -e "${BLUE}>> 正在同步: $module_name${NC}"
                    repo_path="$REPO_DIR/dotfiles/$module_name"
                    mkdir -p "$repo_path"

                    # 1. 物理同步到仓库 (不删除任何东西)
                    cp -rf "$selected_path"/. "$repo_path/" 2>/dev/null

                    # 2. 核心：Stow --adopt (采纳现有的物理文件，建立链接)
                    cd "$REPO_DIR/dotfiles"
                    # --adopt 会处理家目录已存在的物理文件，将其与仓库关联
                    stow -t ~ --adopt "$module_name" 2>/dev/null
                    
                    # 3. 二次覆盖仓库：确保仓库里的内容是备份里的版本，而不是被 adopt 强制吸纳的旧版本
                    cp -rf "$selected_path"/. "$repo_path/" 2>/dev/null
                    echo -e "${GREEN}✅ $module_name 链接已建立。${NC}"
                fi
            done
        fi
    fi

    # Snapper 检测部分
    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> Snapper 已就绪。${NC}"
    fi
}