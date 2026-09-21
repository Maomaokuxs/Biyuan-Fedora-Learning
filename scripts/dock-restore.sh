#!/bin/bash
# 还原窗口：dock-restore.sh <window-id> [target-idx]
# target-idx 缺省为当前聚焦工作区；dock 会传入最小化时记录的原 idx。
ID="$1"
TARGET="$2"
[ -z "$ID" ] && { echo "usage: $0 <window-id> [target-idx]" >&2; exit 1; }
if [ -z "$TARGET" ]; then
    TARGET=$(niri msg -j workspaces 2>/dev/null | jq -r '[.[] | select(.is_focused)] | .[0].idx // 1')
fi
niri msg action move-window-to-workspace --window-id "$ID" "$TARGET"
niri msg action focus-window --id "$ID"
# 收纳区空了就隐身，保持 overview 干净；下次最小化时自动重建
STASH_WS=$(niri msg -j workspaces 2>/dev/null | jq -r '.[] | select(.name=="__dockmin__") | .id')
if [ -n "$STASH_WS" ] && [ "$STASH_WS" != "null" ]; then
    LEFT=$(niri msg -j windows 2>/dev/null | jq --argjson ws "$STASH_WS" '[.[] | select(.workspace_id==$ws)] | length')
    [ "$LEFT" = "0" ] && niri msg action unset-workspace-name "__dockmin__" >/dev/null 2>&1
fi
