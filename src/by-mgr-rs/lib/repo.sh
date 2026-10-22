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
# 仓库 URL 是否使用 $releasever（版本相关仓库才谈得上"只是没跟上当前版本"）
repo_uses_releasever() {
    local id="$1" f in_sec=0 line
    for f in /etc/yum.repos.d/*.repo /usr/share/dnf5/repos.d/*.repo /etc/dnf/repos.d/*.repo; do
        [ -f "$f" ] || continue
        in_sec=0
        while IFS= read -r line; do
            case "$line" in
                "[$id]") in_sec=1 ;;
                "["*"]") in_sec=0 ;;
            esac
            if [ "$in_sec" = 1 ]; then
                case "$line" in
                    *'$releasever'*) return 0 ;;
                esac
            fi
        done < "$f"
    done
    return 1
}

# 当前版本探不通时分辨：URL 带 $releasever 且换上一版本能探通 → 只是没支持当前版本
repo_lagging_only() {
    local id="$1" cur prev
    cur=$(rpm -E %fedora 2>/dev/null)
    case "$cur" in ''|*[!0-9]*) return 1 ;; esac
    prev=$((cur - 1))
    [ "$prev" -ge 1 ] || return 1
    repo_uses_releasever "$id" || return 1
    dnf --releasever="$prev" --disablerepo="*" --enablerepo="$id" --setopt=skip_if_unavailable=False makecache --refresh &>/dev/null
}

clean_repos() {
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo ">> 正在探测 404/失效的仓库（探测阶段不修改系统）..."
    else
        echo ">> 正在探测 404/失效的仓库..." >> "$LOG_DIR/repo.log" 2>&1
    fi
    _sudo_guard "仓库清理" || exit 1
    local out id fail_list=""
    out=$(dnf repolist --enabled 2>/dev/null || true)
    # 第一段：只探测分类、不动系统；中断也只停在这一段，不会禁错任何仓库
    while IFS= read -r line; do
        id=$(echo "$line" | awk '{print $1}')
        [[ -z "$id" || "$id" == Repo* ]] && continue
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            printf "  检查 %s ... " "$id"
        else
            echo "  检查 $id ..." >> "$LOG_DIR/repo.log" 2>&1
        fi
        if dnf --disablerepo="*" --enablerepo="$id" --setopt=skip_if_unavailable=False makecache --refresh &>/dev/null; then
            [ -z "${BY_MGR_QUIET:-}" ] && echo "OK" || echo "OK" >> "$LOG_DIR/repo.log" 2>&1
        elif repo_lagging_only "$id"; then
            # 仓库本身正常、只是还没支持当前 Fedora 版本：只提示，不禁用
            [ -z "${BY_MGR_QUIET:-}" ] && echo "未支持 Fedora $(rpm -E %fedora) → 保留" || echo "未支持当前 Fedora 版本 → 保留" >> "$LOG_DIR/repo.log" 2>&1
        else
            [ -z "${BY_MGR_QUIET:-}" ] && echo "FAIL → 待禁用" || echo "FAIL → 待禁用" >> "$LOG_DIR/repo.log" 2>&1
            fail_list="$fail_list $id"
        fi
    done < <(echo "$out" | tail -n +2)
    # 第二段：名单先落盘，再统一禁用；每禁一个即时记日志，中断也有完整记录
    if [ -n "$fail_list" ]; then
        echo "[$(date +%H:%M:%S)] 待禁用名单:$fail_list" >> "$LOG_DIR/repo.log"
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo ">> 探测完成，开始禁用失效仓库..."
        fi
        # 探测可能耗时很久，禁用前续一次 sudo 凭据，避免第二段因凭据过期卡住
        sudo -v 2>/dev/null || true
        for id in $fail_list; do
            disable_repo_compat "$id" || true
            echo "[$(date +%H:%M:%S)] 已禁用: $id" >> "$LOG_DIR/repo.log"
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo "  已禁用 $id"
            fi
        done
    fi
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
    local enabled_ids
    enabled_ids=$(echo "$enabled" | tail -n +2 | awk '{print $1}')
    while IFS= read -r t; do
        t=$(echo "$t" | xargs)
        [[ -z "$t" || "$t" == \#* ]] && continue
        kind=$(echo "$t" | awk '{print $1}'); id=$(echo "$t" | awk '{print $2}')
        echo "$enabled_ids" | grep -qxF "$id" && continue
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
