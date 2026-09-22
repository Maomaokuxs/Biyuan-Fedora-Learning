import QtQuick
import Quickshell.Io
import "../components" as Comp

// Niri 工作区弹性指示器：暗色小方块，active 展宽 42px（对齐 waybar CSS）
Row {
    id: root
    property var theme
    property string screenName: ""
    spacing: 3
    // ListModel 原位更新：同 idx 的 delegate 存活，宽度动画才能播；
    // 若每次换新数组，Repeater 重建全部 delegate，切换直接闪现毫无动画。
    ListModel { id: wsModel }

    property string _lastJson: ""
    // dock 最小化收纳用的隐藏工作区，不以 pill 显示
    property string hiddenWs: "__dockmin__"

    // 防抖 + 单发刷新：切换瞬间 niri 连发多个事件（Activated /
    // ActiveWindowChanged + WorkspacesChanged），若每次都动 model，
    // 高亮会在中间态之间横跳 = 全体颤抖。120ms 合并为一次；
    // 全量查询进程单发串行，防乱序回包覆盖新状态。
    property var pendingWs: null
    property bool procBusy: false
    property bool procQueued: false

    Timer {
        id: debounce
        interval: 120
        onTriggered: {
            if (root.pendingWs) {
                var a = root.pendingWs;
                root.pendingWs = null;
                root.handleArray(a);
            } else {
                root.requestRefresh();
            }
        }
    }

    function handleEventLine(line) {
        var hit = false;
        if (line.indexOf("WorkspacesChanged") !== -1) {
            try {
                root.pendingWs = JSON.parse(line).WorkspacesChanged.workspaces || [];
                hit = true;
            } catch (e) {}
        } else if (line.indexOf("Workspace") !== -1 || line.indexOf("OutputsChanged") !== -1) {
            hit = true;
        }
        if (hit)
            debounce.restart();
    }

    function requestRefresh() {
        if (procBusy) {
            procQueued = true;
            return;
        }
        procBusy = true;
        wsProc.running = true;
    }

    function handleArray(all) {
        var f = [];
        for (var i = 0; i < all.length; i++) {
            if (all[i].name === root.hiddenWs)
                continue;
            if (!all[i].output || all[i].output === root.screenName || root.screenName === "")
                f.push(all[i]);
        }
        f.sort(function (a, b) { return (a.idx || 0) - (b.idx || 0); });
        root.syncWorkspaces(f);
    }

    function syncWorkspaces(arr) {
        var i, j, k, at, found;
        for (i = wsModel.count - 1; i >= 0; i--) {
            found = false;
            for (j = 0; j < arr.length; j++) {
                if (arr[j].idx === wsModel.get(i).idx) { found = true; break; }
            }
            if (!found)
                wsModel.remove(i);
        }
        for (k = 0; k < arr.length; k++) {
            var active = (arr[k].is_active === true || arr[k].is_focused === true);
            at = -1;
            for (var m = 0; m < wsModel.count; m++) {
                if (wsModel.get(m).idx === arr[k].idx) { at = m; break; }
            }
            if (at === -1) {
                wsModel.insert(k, { idx: arr[k].idx, active: active });
            } else {
                if (at !== k)
                    wsModel.move(at, k, 1);
                wsModel.set(k, { idx: arr[k].idx, active: active });
            }
        }
    }

    Timer {
        interval: 3000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: root.requestRefresh()
    }

    Process {
        id: wsProc
        command: ["bash", "-c", "niri msg -j workspaces 2>/dev/null || echo '[]'"]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = this.text.trim();
                // 无变化不重赋值：同样保护 delegate 存活
                if (raw !== root._lastJson) {
                    try {
                        var all = JSON.parse(raw);
                        // 只保留本屏工作区；无 output 字段时全显。
                        // niri 回的数组不按 idx 排序（实测 3,2,4,1），必须按 idx 排，
                        // 否则 pill 位置错乱、active 高亮落在错误格子上（waybar 同样按 idx 排）。
                        var f = [];
                        for (var i = 0; i < all.length; i++) {
                            if (all[i].name === root.hiddenWs)
                                continue;
                            if (!all[i].output || all[i].output === root.screenName || root.screenName === "")
                                f.push(all[i]);
                        }
                        f.sort(function (a, b) { return (a.idx || 0) - (b.idx || 0); });
                        root._lastJson = raw;
                        root.syncWorkspaces(f);
                    } catch (e) {}
                }
                root.procBusy = false;
                if (root.procQueued) {
                    root.procQueued = false;
                    root.requestRefresh();
                }
            }
        }
    }

    // niri 事件流常驻：切换瞬间即达
    Process {
        id: eventStream
        command: ["bash", "-c", "niri msg --json event-stream 2>/dev/null"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => root.handleEventLine(data)
        }
        onExited: respawnTimer.restart()
    }
    Timer {
        id: respawnTimer
        interval: 2000
        onTriggered: eventStream.running = true
    }

    Repeater {
        model: wsModel
        Rectangle {
            required property int idx
            required property bool active
            required property int index
            property bool isActive: active
            // hover 用 scale 而不用改 width：改 width 会推动 Row 布局，
            // pill 在鼠标下滑来滑去 → entered/exited 疯狂互触发 = 全体颤抖。
            // scale 只影响自身绘制，不触发布局，无反馈环。
            property bool hovered: false
            width: isActive ? 36 : 14
            height: isActive ? 24 : 20
            scale: (hovered && !isActive) ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutCubic } }
            anchors.verticalCenter: parent.verticalCenter
            radius: isActive ? 6 : 4
            color: isActive ? root.theme.fg : Qt.alpha(root.theme.fg, 0.35)
            Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
            Behavior on color { ColorAnimation { duration: 240 } }

            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: parent.hovered = true
                onExited: parent.hovered = false
                onClicked: {
                    Comp.Exec.sh("niri msg action focus-workspace " + parent.idx);
                }
            }
        }
    }
}
