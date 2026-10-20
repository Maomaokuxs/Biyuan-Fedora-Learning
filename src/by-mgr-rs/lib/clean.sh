#!/bin/bash
# lib/clean.sh — 清理快照
# 用法: clean.sh -k <N> | -d <天数>
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"
LOG_FILE="$LOG_DIR/clean.log"
mkdir -p "$LOG_DIR"
mapfile -t time_list < <(list_snapshots)
count=${#time_list[@]}
echo "[$(date +%H:%M:%S)] clean START $* count=$count" > "$LOG_FILE"
if [ "$count" -eq 0 ]; then
    echo -e "${YELLOW}（无快照）${NC}" | tee -a "$LOG_FILE"
    exit 0
fi

if [ -z "$1" ]; then
    echo "清理模式: 1) 按数量保留最近 N 个  2) 按日期删除 N 天前"
    echo "当前快照数: $count"
    for i in "${!time_list[@]}"; do echo "  $((i+1))) $(basename "${time_list[i]}")"; done
    read -p "选择模式 [1/2] (0 返回): " m < /dev/tty
    case "$m" in
        1) read -p "保留最近 N 个 (当前共 $count 个，输入 N): " k < /dev/tty; exec bash "$0" -k "$k" ;;
        2) read -p "删除 N 天前的 (输入 N): " d < /dev/tty; exec bash "$0" -d "$d" ;;
        *) echo "已取消"; exit 0 ;;
    esac
fi
case "$1" in
    -k)
        keep="$2"
        [[ "$keep" =~ ^[0-9]+$ ]] && [ "$keep" -lt "$count" ] || { echo "无效数量 (当前共 $count 个，需 0 ≤ N < $count)" >&2; exit 1; }
        remove_count=$((count - keep))
        echo "[$(date +%H:%M:%S)] clean -k keep=$keep remove=$remove_count" >> "$LOG_FILE"
        for ((i=0; i<remove_count; i++)); do
            if [ -z "${BY_MGR_QUIET:-}" ]; then
                echo "删除 $((i+1))/$remove_count: $(basename "${time_list[i]}")" | tee -a "$LOG_FILE"
            else
                echo "删除 $((i+1))/$remove_count: $(basename "${time_list[i]}")" >> "$LOG_FILE"
            fi
            rm -rf "${time_list[i]}" 2>>"$LOG_FILE" || true
        done
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo -e "${GREEN}✅ 已清理 $remove_count 个旧快照，保留 $keep 个。${NC}" | tee -a "$LOG_FILE"
        else
            echo "✅ 已清理 $remove_count 个旧快照，保留 $keep 个。" | tee -a "$LOG_FILE"
        fi
        echo "[$(date +%H:%M:%S)] clean DONE -k" >> "$LOG_FILE"
        ;;
    -d)
        days="$2"
        [[ "$days" =~ ^[0-9]+$ ]] || { echo "无效天数" >&2; exit 1; }
        threshold=$(date -d "$days days ago" +%Y%m%d%H%M%S)
        echo "[$(date +%H:%M:%S)] clean -d days=$days threshold=$threshold" >> "$LOG_FILE"
        del_count=0
        for s in "${time_list[@]}"; do
            stime=$(echo "$(basename "$s")" | tr -d '_')
            if [ "$stime" -lt "$threshold" ]; then
                if [ -z "${BY_MGR_QUIET:-}" ]; then
                    echo "删除 $s" | tee -a "$LOG_FILE"
                else
                    echo "删除 $s" >> "$LOG_FILE"
                fi
                rm -rf "$s" 2>>"$LOG_FILE" || true
                del_count=$((del_count+1))
            fi
        done
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo -e "${GREEN}✅ 已清理 $del_count 个 $days 天前的快照。${NC}" | tee -a "$LOG_FILE"
        else
            echo "✅ 已清理 $del_count 个 $days 天前的快照。" | tee -a "$LOG_FILE"
        fi
        echo "[$(date +%H:%M:%S)] clean DONE -d" >> "$LOG_FILE"
        ;;
    *) echo "用法: clean.sh -k <N> | -d <天数>" >&2; exit 1 ;;
esac
