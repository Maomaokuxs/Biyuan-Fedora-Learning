setup_snapper() {
    echo -e "${BLUE}=====================================================${NC}"
    echo -e "${GREEN}  [系统阶段 1] 系统底层保护：Snapper 挂载点配置${NC}"
    echo -e "${BLUE}=====================================================${NC}"
    
    if ! command -v snapper &> /dev/null; then sudo dnf install -y snapper; fi

    echo -e "正在检测可创建快照的 Btrfs 子卷...\n"
    mapfile -t subvolumes < <(findmnt -nt btrfs -o TARGET)
    [ ${#subvolumes[@]} -eq 0 ] && { echo -e "${RED}未检测到 Btrfs 挂载点，跳过配置。${NC}\n"; return; }

    local default_indices=""
    for i in "${!subvolumes[@]}"; do
        local clean_path=$(echo "${subvolumes[i]}" | sed 's/[^/]*//')
        [[ "$clean_path" == "/" || "$clean_path" == "/home" ]] && default_indices+="$((i+1)) "
    done
    default_indices=$(echo "$default_indices" | xargs)

    echo -e "发现以下挂载点:"
    for i in "${!subvolumes[@]}"; do echo "  $((i+1))) ${subvolumes[i]}"; done
    echo "  0) 跳过此步骤"
    
    local prompt_text="请输入选项 (多选空格隔开"
    [ -n "$default_indices" ] && prompt_text+="，回车默认 [$default_indices]): " || prompt_text+="): "
    
    read -p "$prompt_text" choices
    [[ -z "$choices" ]] && choices="$default_indices"
    [[ -z "$choices" || "$choices" == "0" ]] && return

    for idx in $choices; do
        if ! [[ "$idx" =~ ^[0-9]+$ ]] || [ "$idx" -lt 1 ] || [ "$idx" -gt "${#subvolumes[@]}" ]; then continue; fi

        local sub_display="${subvolumes[$((idx-1))]}"
        local clean_sub=$(echo "$sub_display" | sed 's/[^/]*//')
        local config_name=$(echo "$clean_sub" | sed 's/\///g')
        [ -z "$config_name" ] && config_name="root"
        
        echo -e "\n${BLUE}--- 处理挂载点: $sub_display ---${NC}"
        if [ -f "/etc/snapper/configs/$config_name" ]; then
            echo -e "${YELLOW}警告: 挂载点 $clean_sub 已配置。${NC}"
            read -p "是否重新配置？[y/N]: " reconf
            [[ $reconf != [yY] ]] && continue
            sudo snapper -c "$config_name" delete-config
        fi

        if sudo snapper -c "$config_name" create-config "$clean_sub"; then
            echo -e "${GREEN}✅ $sub_display 快照配置完成。${NC}"
        else
            echo -e "${RED}❌ $sub_display 快照配置失败！${NC}"
        fi
    done
    echo "" 
}