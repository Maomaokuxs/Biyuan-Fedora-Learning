#!/bin/bash
# dock 状态聚合：一次输出 windows + workspaces，避免 QML 两次轮询竞态
W=$(niri msg -j windows 2>/dev/null || echo '[]')
S=$(niri msg -j workspaces 2>/dev/null || echo '[]')
jq -cn --argjson w "$W" --argjson s "$S" '{windows:$w, workspaces:$s}'
