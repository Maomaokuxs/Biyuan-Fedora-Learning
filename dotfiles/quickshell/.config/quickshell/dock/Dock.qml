import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets
import "../components" as Comp

// Dock v4：纯活跃窗口切换器（任务栏模式）
//
// - 只显示正在运行的窗口，没有窗口的应用不占位（无启动器）。
// - 同一应用的窗口合并为一个图标，左键轮切；运行点 + 收纳角标指示状态。
// - 顺序稳定：聚焦/轮切绝不重排，新应用追加末尾；左键长按拿起拖拽排序
//   （静止按住 280ms，或按住 250ms 后移动超 12px 即起拖），
//   被拖图标放大+提起 10px 跟手，其余图标收拢填坑并在落点让缝，松手落位。
// - 最小化是次要操作（右键），收纳窗口以内联角标显示在所属应用图标上，点击还原。
// - 收发逻辑在 scripts/dock-{ensure-stash,minimize,restore}.sh。
Row {
    id: root
    property var theme
    spacing: 6

    // 每次按下即上报，shell 侧刷新保护期并取消隐藏计时
    signal interacted()

    property string minWs: "__dockmin__"

    property var enriched: []     // 全部窗口（含 ws 名/idx/min 标记，按最近聚焦排序）
    property var groups: []       // 按应用合并：{key, appId, visible, minimized}
    // 稳定顺序：只在首次出现时追加、消失时移除，聚焦变化绝不重排。
    // 长按拖拽改 orderKeys 后 rebuild 原样尊重该顺序。
    property var orderKeys: []
    property var origWs: ({})     // winId -> {idx, wsId, output}
    property int focusedIdx: 1
    // 拖拽态（见下方 startDrag/dragMove/endDrag）
    property string dragKey: ""
    property real dragPressRowX: 0
    property real dragCurRowX: 0
    // 按下点（起拖助攻用）：按住就走的手势不依赖 pressAndHold 计时
    property real pressRowX: 0
    property double pressTime: 0
    // 当前确认的落位槽（带迟滞，不随手抖横跳）；-1 = 未开始
    property int dragTarget: -1
    property bool suppressClick: false
    property bool pendingRefresh: false

    // ---------- 状态拉取：聚合脚本 + 事件流即时刷新 ----------
    Timer {
        id: poller
        interval: 1500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: { if (!stateProc.running) stateProc.running = true; }
    }
    Process {
        id: stateProc
        command: ["bash", Comp.Exec.scriptDir + "/dock-state.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                // 拖拽中不重建 delegate（否则按住丢失），落地再补一次
                if (root.dragKey !== "") { root.pendingRefresh = true; return; }
                try {
                    var o = JSON.parse(this.text);
                    root.ingest(o.windows || [], o.workspaces || []);
                } catch (e) {}
            }
        }
    }
    Process {
        id: eventStream
        command: ["bash", "-c", "niri msg --json event-stream 2>/dev/null"]
        running: true
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                if (data.indexOf("WindowOpened") !== -1 || data.indexOf("WindowClosed") !== -1
                    || data.indexOf("WindowFocusChanged") !== -1 || data.indexOf("WorkspacesChanged") !== -1
                    || data.indexOf("WorkspaceActivated") !== -1)
                    refreshSoon.restart();
            }
        }
        onExited: respawnTimer.restart()
    }
    Timer { id: respawnTimer; interval: 2000; onTriggered: eventStream.running = true }
    Timer { id: refreshSoon; interval: 120; onTriggered: { if (!stateProc.running) stateProc.running = true; } }

    function ingest(windows, workspaces) {
        var wsById = {};
        var fIdx = 1;
        for (var i = 0; i < workspaces.length; i++) {
            wsById[workspaces[i].id] = workspaces[i];
            if (workspaces[i].is_focused) fIdx = workspaces[i].idx;
        }
        root.focusedIdx = fIdx;
        var list = [];
        for (var k = 0; k < windows.length; k++) {
            var w = windows[k];
            var ws = wsById[w.workspace_id] || null;
            var wsName = ws ? (ws.name || "") : "";
            list.push({
                id: w.id,
                app_id: w.app_id || "",
                title: w.title || "",
                workspace_id: w.workspace_id,
                wsName: wsName,
                wsIdx: ws ? ws.idx : fIdx,
                is_focused: w.is_focused === true,
                is_urgent: w.is_urgent === true,
                is_minimized: wsName === root.minWs,
                ts: (w.focus_timestamp && w.focus_timestamp.secs) ? w.focus_timestamp.secs : 0
            });
        }
        list.sort(function (a, b) { return b.ts - a.ts; });
        root.enriched = list;
        root.rebuild();
    }

    // app_id 归一化：去 ".desktop" 后缀、转小写，避免同应用散成多组
    function appKey(appId) {
        var k = (appId || "unknown").toLowerCase();
        if (k.endsWith(".desktop")) k = k.slice(0, -8);
        return k;
    }

    function rebuild() {
        var map = {};
        for (var i = 0; i < root.enriched.length; i++) {
            var w = root.enriched[i];
            var key = root.appKey(w.app_id);
            if (!map[key]) map[key] = { key: key, appId: w.app_id, visible: [], minimized: [] };
            if (w.is_minimized) map[key].minimized.push(w);
            else map[key].visible.push(w);
        }
        // 稳定顺序：保留已有相对位置，新 key 追加到末尾
        var next = [];
        for (var a = 0; a < root.orderKeys.length; a++) {
            if (map[root.orderKeys[a]]) next.push(root.orderKeys[a]);
        }
        for (var k in map) {
            if (next.indexOf(k) === -1) next.push(k);
        }
        root.orderKeys = next;
        var g = [];
        for (var j = 0; j < next.length; j++) g.push(map[next[j]]);
        root.groups = g;
    }

    // ---------- 最小化 / 还原（走 scripts，路径经 Comp.Exec 可移植基址） ----------
    function minimizeWindow(w) {
        var rec = {};
        for (var k in root.origWs) rec[k] = root.origWs[k];
        rec[w.id] = { idx: w.wsIdx, wsId: w.workspace_id };
        root.origWs = rec;
        Comp.Exec.sh("bash " + Comp.Exec.scriptDir + "/dock-minimize.sh " + w.id);
        refreshSoon.restart();
    }
    function restoreWindow(w) {
        var o = root.origWs[w.id];
        var target = (o && o.idx) ? o.idx : root.focusedIdx;
        var rec = {};
        for (var k in root.origWs) { if (String(k) !== String(w.id)) rec[k] = root.origWs[k]; }
        root.origWs = rec;
        Comp.Exec.sh("bash " + Comp.Exec.scriptDir + "/dock-restore.sh " + w.id + " " + target);
        refreshSoon.restart();
    }
    function focusWindow(id) {
        Comp.Exec.sh("niri msg action focus-window --id " + id);
    }
    function closeWindow(id) {
        Comp.Exec.sh("niri msg action close-window --id " + id);
    }

    // 左键 = 轮切：全收起则还原最新，否则聚焦“聚焦项的下一个”（无聚焦则聚焦最新）
    function clickGroup(visible, minimized) {
        if (visible.length === 0) {
            if (minimized.length > 0) root.restoreWindow(minimized[0]);
            return;
        }
        var at = -1;
        for (var i = 0; i < visible.length; i++) {
            if (visible[i].is_focused) { at = i; break; }
        }
        root.focusWindow(visible[(at + 1) % visible.length].id);
    }
    function minimizeOne(visible) {
        if (visible.length === 0) return;
        for (var i = 0; i < visible.length; i++) {
            if (visible[i].is_focused) { root.minimizeWindow(visible[i]); return; }
        }
        root.minimizeWindow(visible[0]);
    }

    // ---------- 长按拖拽排序 ----------
    // 拖拽拿起期间窗体多留一个槽位，给空隙位移腾地方，避免右侧图标被窗体裁掉；
    // 放下即收回。行宽 = 图标 48 + 间距 6 = 54。
    property real dragStep: 54
    property real gapExtra: root.dragKey !== "" ? root.dragStep : 0
    function startDrag(key, rowX) {
        if (root.dragKey !== "") return;
        root.dragKey = key;
        root.dragPressRowX = rowX;
        root.dragCurRowX = rowX;
        root.dragTarget = root.orderKeys.indexOf(key);
        root.suppressClick = true;
    }
    // 起拖助攻：pressAndHold 要求静止按住才触发，按住就走的手势靠这里接管——
    // 左键按住 250ms 后位移超 12px 即起拖，起拖点记最初按下处，图标立刻跟手。
    function notePress(rowX) {
        root.pressRowX = rowX;
        root.pressTime = Date.now();
    }
    function maybeStartDrag(key, rowX) {
        if (root.dragKey !== "") return;
        if (Date.now() - root.pressTime < 250) return;
        if (Math.abs(rowX - root.pressRowX) < 12) return;
        root.startDrag(key, root.pressRowX);
        root.dragMove(rowX);
    }
    function dragMove(rowX) {
        if (root.dragKey === "") return;
        root.dragCurRowX = rowX;
        var from = root.orderKeys.indexOf(root.dragKey);
        if (from === -1) return;
        var raw = from + Math.round((rowX - root.dragPressRowX) / root.dragStep);
        raw = Math.max(0, Math.min(root.orderKeys.length - 1, raw));
        if (root.dragTarget === -1) { root.dragTarget = raw; return; }
        // 迟滞：必须过槽中线 8px 才换槽，手抖不横跳
        var t = root.dragTarget;
        var guard = 0;
        while (t !== raw && guard++ < 10) {
            var dir = raw > t ? 1 : -1;
            var edge = root.dragPressRowX + (t - from) * root.dragStep + dir * (root.dragStep / 2 + 8);
            if ((dir === 1 && rowX >= edge) || (dir === -1 && rowX <= edge)) t += dir;
            else break;
        }
        root.dragTarget = t;
    }
    function dragTargetIndex() {
        if (root.dragTarget !== -1) return root.dragTarget;
        return Math.max(0, root.orderKeys.indexOf(root.dragKey));
    }
    // 拖拽位移（macOS 式）：被拖图标视为已摘出，其余图标先收拢填坑，
    // 再在落点 t 处让缝。f = 拖出槽，t = 落位槽。
    // t > f：(f, t] 左移 54 填坑，被拖图标跟手走，缝自然留在 t 处；
    // t < f：[t, f) 右移 54 让缝，f 之后不动（填坑与让缝抵消）。
    function gapShift(key, idx) {
        if (root.dragKey === "" || root.dragTarget === -1) return 0;
        if (key === root.dragKey) return 0;
        var f = root.orderKeys.indexOf(root.dragKey);
        var t = root.dragTarget;
        if (t === f) return 0;
        if (t > f) return (idx > f && idx <= t) ? -root.dragStep : 0;
        return (idx >= t && idx < f) ? root.dragStep : 0;
    }
    // 被拖图标跟手位移（行内坐标），钳制在行内不飞出去
    function dragFollowX() {
        var f = root.orderKeys.indexOf(root.dragKey);
        if (f === -1) return 0;
        var dx = root.dragCurRowX - root.dragPressRowX;
        var minX = -f * root.dragStep - 16;
        var maxX = (root.orderKeys.length - 1 - f) * root.dragStep + 16;
        return Math.max(minX, Math.min(maxX, dx));
    }
    function endDrag() {
        if (root.dragKey === "") return;
        var idx = root.dragTargetIndex();
        var arr = root.orderKeys.slice();
        var from = arr.indexOf(root.dragKey);
        if (from !== -1 && from !== idx) {
            var k = arr.splice(from, 1)[0];
            arr.splice(idx, 0, k);
            root.orderKeys = arr;
        }
        root.dragKey = "";
        root.rebuild();
        if (root.pendingRefresh) { root.pendingRefresh = false; refreshSoon.restart(); }
    }

    function iconSource(appId) {
        try {
            var e = DesktopEntries.byId(appId);
            if (!e) e = DesktopEntries.heuristicLookup(appId);
            if (e && e.icon) return Quickshell.iconPath(e.icon, "image-missing");
        } catch (err) {}
        return "";
    }

    // ---------- UI：应用分组图标 ----------
    Repeater {
        model: root.groups
        Rectangle {
            required property var modelData
            required property int index
            property var vis: modelData.visible
            property var mini: modelData.minimized
            property string appId: modelData.appId
            property string gkey: modelData.key
            property bool hovered: false
            // 是否正在被拖拽（长按拿起的那个）
            property bool dragging: root.dragKey !== "" && root.dragKey === gkey
            function hasFocused(): boolean {
                for (var i = 0; i < vis.length; i++) if (vis[i].is_focused) return true;
                return false;
            }
            function hasUrgent(): boolean {
                for (var i = 0; i < vis.length; i++) if (vis[i].is_urgent) return true;
                return false;
            }
            property bool focused: hasFocused()
            property bool urgent: hasUrgent()
            property bool allMin: vis.length === 0 && mini.length > 0

            // 固定 48：hover 只换色，绝不改宽高。改宽高会推动 Row 布局、
            // 面板跟着居中位移，鼠标反复进出 hover 区 = 抖动（Workspaces 已验证过）。
            // 拖拽用 scale（只影响绘制，不触发布局，无反馈环）。
            width: 48
            height: 48
            radius: 14
            anchors.verticalCenter: parent.verticalCenter
            scale: dragging ? 1.2 : 1
            Behavior on scale { NumberAnimation { duration: 120 } }
            z: dragging ? 20 : 1
            opacity: (!dragging && allMin) ? 0.55 : 1
            // 位移全走 transform（只影响绘制，不触发布局，无抖动）：
            // 普通图标是填坑/让缝的平滑位移；被拖图标 1:1 跟手 + 微微提起 10px。
            transform: [
                Translate {
                    x: root.gapShift(gkey, index)
                    Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                },
                Translate {
                    id: followT
                    x: dragging ? root.dragFollowX() : 0
                    y: dragging ? -10 : 0
                    Behavior on y { NumberAnimation { duration: 120 } }
                }
            ]
            // 高亮 = 壁纸主题色 accent 本色；平时是压暗的壁纸色；悬停加亮。
            // 字/点一律 fg，保证昼夜都有对比（夜间 fg 白字落在深色按钮上）。
            // 换色同样中心开花（与 Pill 同节奏）
            property int transDelay: {
                var pw = parent ? parent.width : 0;
                if (pw <= 0)
                    return 0;
                return Math.round(Math.abs((x + width / 2) - pw / 2) * 0.3);
            }
            Behavior on color {
                SequentialAnimation {
                    PauseAnimation { duration: transDelay }
                    ColorAnimation { duration: 900; easing.type: Easing.InOutQuad }
                }
            }
            color: urgent ? "#c0392b" : (focused ? root.theme.dockHi : (hovered ? Qt.lighter(root.theme.dockHi, 1.2) : root.theme.dockBtn))
            border.width: mini.length > 0 ? 2 : 0
            border.color: root.theme.fg

            Item {
                anchors.fill: parent
                IconImage {
                    anchors.centerIn: parent
                    implicitSize: 28
                    source: root.iconSource(appId)
                    visible: source.toString() !== ""
                }
                Text {
                    anchors.centerIn: parent
                    visible: root.iconSource(appId) === ""
                        text: (appId || "?").charAt(0).toUpperCase()
                        font.pixelSize: 22; font.bold: true
                        font.family: root.theme.fontFamily
                        color: root.theme.fg
                }
            }
            // 窗口数指示点（最多 3 个）
            Row {
                visible: vis.length > 0
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 4
                spacing: 2
                Repeater {
                    model: Math.min(vis.length, 3)
                        Rectangle { width: 5; height: 5; radius: 2.5; color: root.theme.fg }
                }
            }
            // 已收纳角标
            Rectangle {
                visible: mini.length > 0
                anchors.top: parent.top
                anchors.right: parent.right
                anchors.topMargin: -4; anchors.rightMargin: -4
                width: 18; height: 18; radius: 9
                color: root.theme.clockBg
                Text {
                    anchors.centerIn: parent
                    text: mini.length
                    font.pixelSize: 11; font.bold: true
                    color: root.theme.clockFg
                }
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                pressAndHoldInterval: 280
                onEntered: parent.hovered = true
                onExited: parent.hovered = false
                onPressed: mouse => { root.interacted(); root.notePress(parent.x + mouse.x); }
                // 长按拿起：rowX 用 Row 系坐标（delegate.x 在拖拽中途不变，可放心累积位移）
                // 仅左键可起拖，避免右键长按吞掉最小化
                onPressAndHold: mouse => { if (mouse.button === Qt.LeftButton) root.startDrag(gkey, parent.x + mouse.x); }
                onPositionChanged: e => {
                    // 关键：transform 会作用于 MouseArea 自身，e.x 已扣掉当前视觉位移，
                    // 必须加回 followT.x 才是真正的行坐标，否则图标以一半速度跟随。
                    if (root.dragKey === gkey) { root.dragMove(parent.x + followT.x + e.x); return; }
                    if (e.buttons & Qt.LeftButton) root.maybeStartDrag(gkey, parent.x + e.x);
                }
                onReleased: { if (root.dragKey === gkey) root.endDrag(); }
                onCanceled: { if (root.dragKey === gkey) root.endDrag(); }
                onClicked: e => {
                    // 长按拖拽后的抬起会附带一次 clicked，直接吞掉
                    if (root.suppressClick) { root.suppressClick = false; return; }
                    if (e.button === Qt.RightButton) root.minimizeOne(vis);
                    else if (e.button === Qt.MiddleButton) {
                        if (vis.length > 0) root.closeWindow(vis[0].id);
                        else if (mini.length > 0) root.closeWindow(mini[0].id);
                    } else root.clickGroup(vis, mini);
                }
            }
        }
    }
}
