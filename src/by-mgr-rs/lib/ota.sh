#!/bin/bash
# lib/ota.sh — OTA 自更新（Rust 二进制：git pull + cargo build）
set -e
SCRIPT_DIR=$(dirname "$(readlink -f "$0")")
source "$SCRIPT_DIR/utils.sh"
SELF_PATH="$REPO_DIR/scripts/by-mgr"
BIN_DST="$HOME/.local/bin/by-mgr"
LOG_FILE="$LOG_DIR/ota.log"
mkdir -p "$LOG_DIR"
echo "[$(date +%H:%M:%S)] ota START" > "$LOG_FILE"

# 1. 未提交保护
if git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
    if [ -n "$(git -C "$REPO_DIR" status --porcelain 2>/dev/null)" ]; then
        if [ -z "${BY_MGR_QUIET:-}" ]; then
            echo -e "${YELLOW}⚠️  检测到未提交的本地修改，OTA 已中止以防丢失${NC}" | tee -a "$LOG_FILE" >&2
            echo -e "${YELLOW}   请先执行: git stash 或 git commit${NC}" | tee -a "$LOG_FILE" >&2
        else
            echo "⚠️ 检测到未提交的本地修改，OTA 已中止" | tee -a "$LOG_FILE" >&2
        fi
        git -C "$REPO_DIR" status --porcelain 2>&1 | head -n 20 | tee -a "$LOG_FILE" >&2
        exit 1
    fi
fi

if [ -z "${BY_MGR_QUIET:-}" ]; then
    echo -e "${YELLOW}>> 正在连接远程仓库检查 by-mgr 最新版本...${NC}" | tee -a "$LOG_FILE"
else
    echo ">> 正在连接远程仓库..." >> "$LOG_FILE"
fi

# 2. 判断本地形态：Rust 二进制 (ELF) 还是 Bash
is_rust_local=false
if [ -f "$SELF_PATH" ] && file "$SELF_PATH" 2>/dev/null | grep -q "ELF"; then
    is_rust_local=true
fi

if $is_rust_local; then
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${CYAN}>> 检测到 Rust 二进制，将通过 git pull + cargo build 更新...${NC}" | tee -a "$LOG_FILE"
    else
        echo ">> 检测到 Rust 二进制，将通过 git pull + cargo build 更新..." >> "$LOG_FILE"
    fi
    if ! git -C "$REPO_DIR" rev-parse --is-inside-work-tree &>/dev/null; then
        echo -e "${RED}❌ 非 git 仓库，无法 OTA${NC}" | tee -a "$LOG_FILE" >&2; exit 1
    fi
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${BLUE}>> git pull --ff-only...${NC}" | tee -a "$LOG_FILE"
    else
        echo ">> git pull --ff-only..." >> "$LOG_FILE"
    fi
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        if ! git -C "$REPO_DIR" pull --ff-only 2>&1 | tee -a "$LOG_FILE"; then
            echo -e "${RED}❌ git pull 失败，请手动处理${NC}" | tee -a "$LOG_FILE" >&2; exit 1
        fi
    else
        if ! git -C "$REPO_DIR" pull --ff-only >> "$LOG_FILE" 2>&1; then
            echo "❌ git pull 失败" | tee -a "$LOG_FILE" >&2; exit 1
        fi
    fi
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${BLUE}>> cargo build --release...${NC}" | tee -a "$LOG_FILE"
    else
        echo ">> cargo build --release..." >> "$LOG_FILE"
    fi
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        if ! cargo build --release --manifest-path "$REPO_DIR/src/by-mgr-rs/Cargo.toml" 2>&1 | tee -a "$LOG_FILE"; then
            echo -e "${RED}❌ cargo build 失败${NC}" | tee -a "$LOG_FILE" >&2; exit 1
        fi
    else
        if ! cargo build --release --manifest-path "$REPO_DIR/src/by-mgr-rs/Cargo.toml" >> "$LOG_FILE" 2>&1; then
            echo "❌ cargo build 失败" | tee -a "$LOG_FILE" >&2; exit 1
        fi
    fi
    cp -f "$REPO_DIR/src/by-mgr-rs/target/release/by-mgr" "$SELF_PATH" && chmod +x "$SELF_PATH"
    mkdir -p "$(dirname "$BIN_DST")"
    cp -f "$SELF_PATH" "$BIN_DST" 2>/dev/null || true
    chmod +x "$BIN_DST" 2>/dev/null || true
    if [ -z "${BY_MGR_QUIET:-}" ]; then
        echo -e "${GREEN}✨ OTA 更新成功 (Rust)！${NC}" | tee -a "$LOG_FILE"
    else
        echo "✅ OTA 更新成功 (Rust)" | tee -a "$LOG_FILE"
    fi
    exit 0
fi

# 3. 非 Rust 形态：旧 Bash 单文件版的下载更新无完整性校验，已移除该路径
echo -e "${RED}❌ 当前 by-mgr 不是 Rust 二进制形态，OTA 已不支持，请先手动安装 Rust 版${NC}" | tee -a "$LOG_FILE" >&2
exit 1
