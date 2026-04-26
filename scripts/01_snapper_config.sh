#!/bin/bash

setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] 快照防护与双源全量配置管理${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    local BACKUP_ROOT="$HOME/.dotfiles_backup"
    
    # --- 1. Snapper 快照模块 (保持稳定) ---
    if ! command -v snapper &> /dev/null || [ ! "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        echo -e "${YELLOW}>> 准备初始化 Snapper...${NC}"
        if ! command -v snapper &> /dev/null; then sudo dnf install -y snapper &> /dev/null; fi
        mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)
        if [ ${#subvolumes[@]} -gt 0 ]; then
            for i in "${!subvolumes[@]}"; do echo "  $((i+1))) ${subvolumes[i]}"; done
            read -p "选择配置编号 (多选空格, 0跳过): " snap_choices
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

    if command -v snapper &> /dev/null && [ "$(ls -A /etc/snapper/configs/ 2>/dev/null)" ]; then
        read -p "🚨 是否在操作前为系统创建一个底层安全快照？[y/N]: " do_snap
        if [[ $do_snap == [yY] ]]; then
            local target_c=$(sudo snapper list-configs | awk 'NR==3 {print $1}')
            [ -z "$target_c" ] && target_c="root"
            sudo snapper -c "$target_c" create --description "Pre_Deployment_Backup"
            echo -e "${GREEN}✅ 系统快照已创建。${NC}"
        fi
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 2. 自动化全量备份模块 (针对仓库涉及的所有应用) ---
    mkdir -p "$BACKUP_ROOT"
    read -p "📦 是否自动备份本地所有受影响的应用配置？[y/N]: " auto_backup
    if [[ $auto_backup == [yY] ]]; then
        local date_tag=$(date +%Y%m%d_%H%M)
        echo -e "${BLUE}>> 正在根据仓库模块扫描并备份本地配置...${NC}"
        
        # 遍历 dotfiles 目录下的所有模块名
        for module in $(ls "$DOTFILES_DIR"); do
            local dest_dir="$BACKUP_ROOT/${module}_${date_tag}"
            
            # 备份逻辑：保持目录结构以便后续 Stow 识别
            if [ -d "$HOME/.config/$module" ]; then
                mkdir -p "$dest_dir/.config/$module"
                cp -r "$HOME/.config/$module/." "$dest_dir/.config/$module/"
                echo -e "${GREEN}  [OK] 备份: .config/$module${NC}"
            fi
            
            # 特殊处理颜色缓存备份
            if [ "$module" == "colors" ] || [ "$module" == "hellwal" ]; then
                if [ -d "$HOME/.cache/hellwal" ]; then
                    mkdir -p "$dest_dir/.cache/hellwal"
                    cp -r "$HOME/.cache/hellwal/." "$dest_dir/.cache/hellwal/"
                    echo -e "${GREEN}  [OK] 备份: .cache/hellwal${NC}"
                fi
            fi
        done
        echo -e "${YELLOW}>> 备份任务完成。${NC}"
    fi

    echo -e "\n${BLUE}-----------------------------------------------------${NC}"

    # --- 3. 双源链接切换与物理恢复模块 ---
    echo -e "${YELLOW}当前配置源管理 (Stow 链接切换):${NC}"
    echo "  1) ☁️  使用仓库最新配置 (链接至 Git)"
    echo "  2) 🕰️  使用历史备份配置 (链接至本地备份库)"
    echo "  3) 📁  物理恢复并解除链接 (断开链接，原位复制)"
    echo "  0) ⏭️  跳过此步骤"
    read -p "请选择操作模式 [0-3]: " source_mode

    if [[ "$source_mode" =~ ^[1-3]$ ]]; then
        read -p "请输入要操作的模块名 (如 niri, waybar): " module_name
        [ -z "$module_name" ] && return

        local target_dir="$HOME/.config/$module_name"
        [ "$module_name" == "colors" ] && target_dir="$HOME/.cache/hellwal"

        # 彻底断开旧的关联
        [ -L "$target_dir" ] || [ -d "$target_dir" ] && rm -rf "$target_dir"

        case "$source_mode" in
            1)
                if [ -d "$DOTFILES_DIR/$module_name" ]; then
                    cd "$DOTFILES_DIR"
                    stow -t ~ "$module_name" 2>/dev/null
                    echo -e "${GREEN}✅ 已链接至 Git 主仓库版本。${NC}"
                fi ;;
            2)
                mapfile -t backups < <(ls -d "$BACKUP_ROOT/${module_name}_"* 2>/dev/null)
                if [ ${#backups[@]} -gt 0 ]; then
                    for i in "${!backups[@]}"; do echo "  $((i+1))) $(basename "${backups[i]}")"; done
                    read -p "选择回滚版本编号: " b_idx
                    if [[ "$b_idx" -gt 0 ]] && [[ "$b_idx" -le "${#backups[@]}" ]]; then
                        selected_pkg=$(basename "${backups[$((b_idx-1))]}")
                        cd "$BACKUP_ROOT"
                        stow -t ~ "$selected_pkg" 2>/dev/null
                        echo -e "${GREEN}✅ 已链接至历史备份版本。${NC}"
                    fi
                fi ;;
            3)
                mapfile -t backups < <(ls -d "$BACKUP_ROOT/${module_name}_"* 2>/dev/null)
                if [ ${#backups[@]} -gt 0 ]; then
                    for i in "${!backups[@]}"; do echo "  $((i+1))) $(basename "${backups[i]}")"; done
                    read -p "选择物理恢复的版本: " b_idx
                    if [[ "$b_idx" -gt 0 ]] && [[ "$b_idx" -le "${#backups[@]}" ]]; then
                        selected_path="${backups[$((b_idx-1))]}"
                        mkdir -p "$target_dir"
                        if [ -d "$selected_path/.cache" ]; then
                            cp -rf "$selected_path/.cache/hellwal/." "$target_dir/"
                        else
                            cp -rf "$selected_path/.config/$module_name/." "$target_dir/"
                        fi
                        echo -e "${GREEN}✅ 物理文件已恢复，当前独立运行。${NC}"
                    fi
                fi ;;
        esac
    fi
}