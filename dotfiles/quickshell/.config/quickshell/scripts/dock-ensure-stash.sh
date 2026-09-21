#!/bin/bash
# 确保最小化收纳工作区存在：复用最底部空工作区并命名。
# niri 的 move-window-to-workspace 只能移往已存在的工作区，
# 往不存在的名字移是静默无操作，所以最小化前必须先 ensure。
MINWS="__dockmin__"
if ! niri msg -j workspaces 2>/dev/null | jq -e --arg n "$MINWS" '[.[] | select(.name==$n)] | length > 0' >/dev/null; then
    EMPTY=$(niri msg -j workspaces 2>/dev/null | jq -r 'max_by(.idx) | .idx')
    [ -n "$EMPTY" ] && [ "$EMPTY" != "null" ] && niri msg action set-workspace-name "$MINWS" --workspace "$EMPTY" >/dev/null 2>&1
fi
