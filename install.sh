#!/bin/bash
# 文件位置: ./install.sh

# --- 0. 自动更新模块 ---
update_self() {
    if [ -d ".git" ] && command -v git &> /dev/null; then
        echo -e "${BLUE}>> 正在检查远程仓库更新...${NC}"
        
        # 预检：静默获取远程状态
        git fetch --quiet
        LOCAL=$(git rev-parse @)
        REMOTE=$(git rev-parse @{u})

        if [ "$LOCAL" != "$REMOTE" ]; then
            # 发现不一致，尝试拉取
            if git pull; then
                echo -e "${GREEN}✅ 仓库代码已更新。${NC}"
                echo -e "${YELLOW}>> 正在同步磁盘缓冲区并重启引擎...${NC}"
                
                # 关键修复 1: 强制将内存中的文件写入落盘，防止脚本读取旧缓存
                sync
                sleep 0.5 
                
                # 关键修复 2: 使用 exec 替换当前进程，并传入跳过更新标记，防止无限死循环
                exec bash "$0" --no-update "$@"
                exit 0
            fi
        fi
    fi
}

# --- 主程序入口 ---
main() {
    # 1. 优先执行自更新
    # 增加 --no-update 拦截，确保重启后的脚本不再进入更新逻辑
    if [[ "$1" != "--no-update" ]]; then
        update_self "$@"
    else
        # 如果是重启进来的，把 --no-update 参数移走，避免影响后续子脚本解析参数
        shift
    fi

    # 2. 只有在自更新判定结束后，才开始定义 REPO_DIR 和 加载子模块
    # 这样能保证加载到的是磁盘上最新的 scripts/*.sh
    REPO_DIR=$(cd "$(dirname "${BASH_SOURCE[0]}")" &> /dev/null && pwd)
    SCRIPTS_DIR="$REPO_DIR/scripts"
    export DOTFILES_DIR="$REPO_DIR/dotfiles"
    
    # 加载色彩定义
    source_colors 2>/dev/null # 假设你有个颜色定义的辅助函数或直接写在这里

    clear
    echo -e "${CYAN}>> 引擎已就绪，正在加载最新配置...${NC}"

    # 3. 加载后续模块 (此时加载的一定是 git pull 之后的最新的脚本)
    if [ -d "$SCRIPTS_DIR" ]; then
        for script in "$SCRIPTS_DIR"/*.sh; do
            if [ -f "$script" ]; then
                chmod +x "$script"
                source "$script"
            fi
        done
    fi

    # 4. 执行后续流程
    setup_snapper_and_backup      
    install_desktop_niri          
}

main "$@"