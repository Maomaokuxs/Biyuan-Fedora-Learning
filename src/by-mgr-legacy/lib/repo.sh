#!/bin/bash
# lib/repo.sh — 仓库管理
# 用法: repo.sh [export|clean|replenish|edit]  无参进入交互菜单
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"

op="${1:-menu}"

export_list() {
    mkdir -p "$USER_CONFIG_DIR"
    local dest="$USER_CONFIG_DIR/repos.list"
    local out
    out=$(dnf repolist --enabled 2>/dev/null || true)
    local lines=("# Biyuan 自动生成的仓库备份清单")
    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        [[ -z "$id" || "$id" == "repo" || "$id" == Repo* || "$id" == "-"* ]] && continue
        lines+=("repo $id")
    done < <(echo "$out" | tail -n +2)
    if [ -f "$REPO_DIR/config/repos.list" ]; then
        while IFS= read -r t; do
            t=$(echo "$t" | xargs)
            [[ -z "$t" ]] && continue
            [[ " ${lines[*]} " == *" $t "* ]] || lines+=("$t")
        done < "$REPO_DIR/config/repos.list"
    fi
    printf "%s\n" "${lines[@]}" > "$dest"
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${GREEN}✅ 已导出到 $dest${NC}"
    else
        echo "✅ 已导出到 $dest"
    fi
}
clean_repos() {
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo ">> 正在探测并禁用 404/失效的仓库..."
    else
        echo ">> 正在探测并禁用 404/失效的仓库..." >> "$LOG_DIR/repo.log" 2>&1
    fi
    _sudo_guard "仓库清理" || exit 1
    local out
    out=$(dnf repolist --enabled 2>/dev/null || true)
    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        [[ -z "$id" || "$id" == Repo* ]] && continue
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            printf "  检查 %s ... " "$id"
        else
            echo "  检查 $id ..." >> "$LOG_DIR/repo.log" 2>&1
        fi
        if dnf --disablerepo="*" --enablerepo="$id" makecache --refresh &>/dev/null; then
            [ -z "${BY_MGR_QUIET:-}" ] && echo "OK" || echo "OK" >> "$LOG_DIR/repo.log" 2>&1
        else
            [ -z "${BY_MGR_QUIET:-}" ] && echo "FAIL → 禁用" || echo "FAIL → 禁用" >> "$LOG_DIR/repo.log" 2>&1
            disable_repo_compat "$id" || true
        fi
    done < <(echo "$out" | tail -n +2)
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${GREEN}✅ 清理完成${NC}"
    else
        echo "✅ 清理完成"
    fi
}
replenish() {
    local src="$USER_CONFIG_DIR/repos.list"
    [ -f "$src" ] || { echo "未找到清单 $src" >&2; exit 1; }
    local enabled
    enabled=$(dnf repolist --enabled 2>/dev/null || true)
    while IFS= read -r t; do
        t=$(echo "$t" | xargs)
        [[ -z "$t" || "$t" == \#* ]] && continue
        kind=$(echo "$t" | awk '{print $1}'); id=$(echo "$t" | awk '{print $2}')
        echo "$enabled" | grep -q "$id" && continue
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo ">> 补齐 $kind $id"
        else
            echo ">> 补齐 $kind $id" >> "$LOG_DIR/repo.log" 2>&1
        fi
        case "$kind" in
            copr) sudo dnf copr enable -y "$id" 2>&1 | tee -a "$LOG_DIR/repo.log" || true ;;
            repo) enable_repo_compat "$id" || true ;;
        esac
    done < "$src"
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${GREEN}✅ 补齐完成${NC}"
    else
        echo "✅ 补齐完成"
    fi
}
edit_list() {
    local path="$USER_CONFIG_DIR/repos.list"
    mkdir -p "$(dirname "$path")"
    if [ ! -f "$path" ]; then
        printf '# Biyuan 仓库清单\n# 每行一个：repo <repoid> 或 copr <author>/<project>\n' > "$path"
    fi
    local editor="${EDITOR:-nano}"
    $editor "$path" || true
}

case "$op" in
    export) export_list ;;
    clean) clean_repos ;;
    replenish) replenish ;;
    edit) edit_list ;;
    menu)
        while true; do
            echo "软件仓库管理: 1) 导出清单 2) 清理失效仓库 3) 增量补齐 4) 编辑清单 0) 返回"
            read -p "选择: " c < /dev/tty 2>/dev/null || read -p "选择: " c
            case "$c" in
                1) export_list ;;
                2) clean_repos ;;
                3) replenish ;;
                4) edit_list ;;
                0) break ;;
                *) echo "已取消" ;;
            esac
        done
        ;;
    *) echo "用法: repo.sh [export|clean|replenish|edit]" >&2; exit 1 ;;
esac
