import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// 左侧工具组：8 件工具（录制/截图/取色/剪贴板/护眼/主题/壁纸/显示器）改为独立胶囊，
// 不再共用一个托盘；拖拽组合/分离与右侧胶囊区同构（zoneLayout + 仓库领养，
// 幽灵走 UiState 全局覆盖窗），分组存 ~/.cache/by-mgr/qs-bar-layout-left.json，重启恢复。
Item {
    id: root
    property var theme
    property string screenName
    property bool forceHidden: false
    property var barState
    property var exec
    property var uiState
    property var icons

    visible: !forceHidden
    Layout.preferredWidth: visible ? toolZone.implicitWidth : 0
    Layout.preferredHeight: 32
    height: 32
    implicitWidth: toolZone.implicitWidth
    implicitHeight: 32

    // ---------- 工具胶囊拖拽区（移植自 Bar.qml pillZone，机制同构）----------
    // zoneLayout = 有序槽位表，槽位是 id 数组：单元素 = 单颗，多元素 = 组合胶囊。
    property var pillMap: ({})
    property var zoneLayout: [["rec"], ["shot"], ["pick"], ["clip"], ["gamma"], ["theme"], ["wall"], ["screen"]]
    property bool zoneReady: false
    property var slotItems: []
    property string dragId: ""
    property bool dragEnding: false   // pillDragEnd 重入守卫：落位 reparent 会同步触发 onCanceled 重入
    property int dragFromSlot: -1
    property string dragTargetType: "none"
    property int dragTargetIndex: -1
    property int dragHighlightIndex: -1
    property string dragHighlightMode: ""

    FileView {
        id: layoutLeftFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-layout-left.json"
        onLoaded: { root.applyLayoutFile(text()); root.zoneReady = true; }
        onLoadFailed: root.zoneReady = true
    }
    // FileView 迟迟不回执时兜底放行（用默认布局），不让整区空白
    Timer {
        interval: 500
        running: true
        onTriggered: root.zoneReady = true
    }
    Component.onCompleted: {
        root.pillMap = { "rec": recPill, "shot": shotPill, "pick": pickPill, "clip": clipPill, "gamma": gammaPill, "theme": themePill, "wall": wallPill, "screen": screenPill };
        console.warn("[toolzone] layout " + JSON.stringify(root.zoneLayout));
    }

    // 窗口坐标：逐级累加祖先 x/y（本 Qt 版本 mapToItem(null) 不可靠，见 Pill.updateAnchor）
    function absPosOf(it) {
        var x = 0, y = 0, n = it;
        var guard = 0;
        while (n && guard++ < 100) {
            x += n.x;
            y += n.y;
            n = n.parent;
        }
        return Qt.point(x, y);
    }
    function registerSlot(idx, item) {
        var a = root.slotItems;
        a[idx] = item;
        root.slotItems = a;
    }
    function unregisterSlot(idx, item) {
        // 按下标置空，禁止 splice：registerSlot 按下标写入，删除若移位会让
        // slotItems 与 zoneLayout 下标错位（命中判定/落位全错，两端最明显）
        var a = root.slotItems;
        if (idx >= 0 && idx < a.length && a[idx] === item)
            a[idx] = null;
        root.slotItems = a;
    }
    function applyLayoutFile(txt) {
        var known = ["rec", "shot", "pick", "clip", "gamma", "theme", "wall", "screen"];
        try {
            var data = JSON.parse(txt);
            if (!Array.isArray(data))
                return;
            var seen = {};
            for (var i = 0; i < data.length; i++) {
                if (!Array.isArray(data[i]) || data[i].length === 0)
                    return;
                for (var j = 0; j < data[i].length; j++) {
                    if (known.indexOf(data[i][j]) < 0 || seen[data[i][j]])
                        return;
                    seen[data[i][j]] = true;
                }
            }
            if (Object.keys(seen).length !== known.length)
                return;
            root.zoneLayout = data;
        } catch (e) {
            return;
        }
        console.warn("[toolzone] layout " + JSON.stringify(root.zoneLayout));
    }
    // 布局变更前把所有工具 pill 送回仓库，避免 Repeater 重建 delegate 时连带销毁
    function rescueAllPills() {
        for (var i = 0; i < root.slotItems.length; i++) {
            var s = root.slotItems[i];
            if (!s)
                continue;
            for (var j = 0; j < s.members.length; j++) {
                s.members[j].bare = false;
                s.members[j].parent = toolWarehouse;
            }
        }
    }
    function pillDragStart(pid) {
        root.dragId = pid;
        root.dragFromSlot = -1;
        for (var i = 0; i < root.zoneLayout.length; i++) {
            if (root.zoneLayout[i].indexOf(pid) >= 0) {
                root.dragFromSlot = i;
                break;
            }
        }
        var pill = root.pillMap[pid];
        if (pill) {
            var ap = root.absPosOf(pill);
            // 幽灵发布给 shell 覆盖窗（先填内容再置 active，避免首帧旧值）
            root.uiState.dragText = pill.pillText;
            root.uiState.dragBg = pill.normalBg;
            root.uiState.dragFg = pill.normalFg;
            root.uiState.dragW = Math.max(pill.width, 40);
            root.uiState.dragX = ap.x + pill.width / 2;
            root.uiState.dragY = ap.y + 16;
        }
        root.uiState.dragScreen = root.screenName;
        root.uiState.dragActive = true;
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
    }
    function pillDragMoved(wx, wy) {
        if (root.dragId === "")
            return;
        root.uiState.dragX = wx;
        root.uiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var inBar = wx >= -20 && wy >= -12 && wy <= 58;
        if (inBar) {
            var hit = -1;
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s || s.width <= 0)
                    continue;
                var sp = root.absPosOf(s);
                if (wx >= sp.x && wx <= sp.x + s.width && wy >= sp.y - 8 && wy <= sp.y + s.height + 8) {
                    hit = i;
                    var fx = (wx - sp.x) / s.width;
                    if (fx < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fx > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(toolZone);
                if (wx >= zp.x - 10 && wx <= zp.x + toolZone.width + 10 && wy >= zp.y - 8 && wy <= zp.y + toolZone.height + 8) {
                    var p = root.slotItems.length;
                    for (var k = 0; k < root.slotItems.length; k++) {
                        var sk = root.slotItems[k];
                        if (!sk)
                            continue;
                        var skp = root.absPosOf(sk);
                        if (wx < skp.x + sk.width / 2) { p = k; break; }
                    }
                    type = "insert"; tIndex = p;
                    if (p < root.slotItems.length) { hlIndex = p; hlMode = "insertL"; }
                    else { hlIndex = root.slotItems.length - 1; hlMode = "insertR"; }
                }
            }
        }
        root.dragTargetType = type;
        root.dragTargetIndex = tIndex;
        root.dragHighlightIndex = hlIndex;
        root.dragHighlightMode = hlMode;
    }
    function pillDragEnd() {
        root.uiState.dragActive = false;
        var pid = root.dragId;
        if (pid === "")
            return;
        if (root.dragEnding) {
            console.warn("[toolzone] dragEnd reentry blocked " + pid);
            return;
        }
        root.dragEnding = true;
        var type = root.dragTargetType;
        var t = root.dragTargetIndex;
        var from = root.dragFromSlot;
        root.dragId = "";
        root.dragHighlightIndex = -1;
        root.dragHighlightMode = "";
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
        root.dragFromSlot = -1;
        if (type === "none" || from < 0) {
            root.dragEnding = false;
            return;
        }
        if (type === "merge" && t === from) {
            root.dragEnding = false;
            return;
        }
        var layout = root.zoneLayout.map(function(a) { return a.slice(); });
        var fromArr = layout[from];
        var fix = fromArr.indexOf(pid);
        if (fix < 0) {
            console.warn("[toolzone] dragEnd abort: " + pid + " not in slot " + from);
            root.dragEnding = false;
            return;
        }
        fromArr.splice(fix, 1);
        var emptied = fromArr.length === 0;
        if (emptied)
            layout.splice(from, 1);
        if (type === "merge") {
            var ti = t - ((emptied && from < t) ? 1 : 0);
            layout[ti].push(pid);
        } else {
            var p = t - ((emptied && from < t) ? 1 : 0);
            if (p < 0) p = 0;
            if (p > layout.length) p = layout.length;
            layout.splice(p, 0, [pid]);
        }
        // 无变化落位（把 pill 拖回自身相邻的插入线等）：给 zoneLayout 赋内容相同的
        // 数组不会触发 QML 变更通知，Repeater 不重建——此时绝不能先营救，
        // 否则全部 pill 滞留仓库、整区空白（已实测复现）
        if (JSON.stringify(layout) === JSON.stringify(root.zoneLayout)) {
            console.warn("[toolzone] dragEnd noop " + pid);
            root.dragEnding = false;
            return;
        }
        root.rescueAllPills();
        root.zoneLayout = layout;
        // 落位自检（取证）：重建后仍滞留仓库的 pill 说明被竞态吞了，打日志留证
        Qt.callLater(function() {
            for (var oid in root.pillMap) {
                var op = root.pillMap[oid];
                if (op && op.parent === toolWarehouse)
                    console.warn("[toolzone] orphan " + oid);
            }
        });
        console.warn("[toolzone] layout " + JSON.stringify(layout));
        root.exec.sh("printf '%s' '" + JSON.stringify(layout).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-left.json");
        root.dragEnding = false;
    }

    // 槽位成员的占位 holder：宽度跟随 pill.animW（显隐动画不破），拖拽中半透明示意占位
    Component {
        id: holderComponent
        Item {
            property string pillId: ""
            property var pillRef: null
            width: pillRef ? pillRef.animW : 0
            height: 32
            clip: true
            opacity: (root.dragId !== "" && root.dragId === pillId) ? 0.35 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // 槽位：单颗直显 pill 本人；组画共享底色 + 成员 bare 并排
    Component {
        id: slotDelegate
        Item {
            id: slot
            property var slotIds: modelData
            property var members: []
            property var anchorPill: null
            property string dropMode: root.dragHighlightIndex === index ? root.dragHighlightMode : ""
            property bool anyShown: {
                for (var i = 0; i < members.length; i++)
                    if (members[i].shown)
                        return true;
                return false;
            }
            height: 32
            width: {
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animW;
                if (members.length >= 2)
                    return anyShown ? s + 2 * (members.length - 1) + 4 : 0;
                return members.length === 1 ? s : 0;
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                visible: slot.slotIds.length >= 2 && slot.anyShown
                color: slot.anchorPill ? slot.anchorPill.normalBg : "transparent"
            }
            Row {
                id: slotRow
                anchors { left: parent.left; leftMargin: slot.slotIds.length >= 2 ? 2 : 0; verticalCenter: parent.verticalCenter }
                spacing: 2
                height: 32
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.width: 2
                border.color: root.theme.clockBg
                visible: slot.dropMode === "merge"
                z: 5
            }
            Rectangle {
                width: 2; height: 32; x: -5
                color: root.theme.clockBg
                visible: slot.dropMode === "insertL"
                z: 5
            }
            Rectangle {
                width: 2; height: 32; x: parent.width + 3
                color: root.theme.clockBg
                visible: slot.dropMode === "insertR"
                z: 5
            }

            Component.onCompleted: {
                var ms = [];
                var isGroup = slotIds.length >= 2;
                for (var i = 0; i < slotIds.length; i++) {
                    var pill = root.pillMap[slotIds[i]];
                    if (!pill)
                        continue;
                    var holder = holderComponent.createObject(slotRow, { "pillId": slotIds[i], "pillRef": pill });
                    pill.parent = holder;
                    pill.x = 0;
                    pill.y = 0;
                    pill.bare = isGroup;
                    ms.push(pill);
                }
                slot.members = ms;
                slot.anchorPill = ms.length > 0 ? ms[0] : null;
                if (isGroup && ms.length > 0) {
                    var ap = ms[0];
                    for (var k = 0; k < ms.length; k++) {
                        (function(p) {
                            p.bareFg = Qt.binding(function() { return ap.normalFg; });
                        })(ms[k]);
                    }
                }
                root.registerSlot(index, slot);
            }
            Component.onDestruction: {
                for (var i = 0; i < members.length; i++) {
                    // 归属守卫（父链判定）：成员的 parent 是本 slot 为它建的 holder
                    // 时才归本 slot 所有；已被新 delegate 领养（parent 换成新 holder）
                    // 或已被 rescueAllPills 送回仓库的，父链已变，一律不碰——
                    // 否则旧 delegate 销毁会把新槽位里的 pill 拽回仓库变空白
                    var mp = members[i].parent;
                    if (!mp || mp.parent !== slotRow)
                        continue;
                    members[i].bare = false;
                    members[i].parent = toolWarehouse;
                }
                root.unregisterSlot(index, slot);
            }
        }
    }

    // 工具仓库：8 件声明停在这里（隐藏不排版），由 toolZone 槽位按 zoneLayout 领养。
    // 点击行为从原托盘逐条迁来（左键/右键/补刷），一条不丢。
    Item {
        id: toolWarehouse
        visible: false
        width: 0
        height: 0

        // 录制
        Pill {
            id: recPill
            pillId: "rec"
            dragEnabled: true
            normalBg: theme.accent
            normalFg: (barState.recC === "recording" || barState.recC === "kernel" || barState.recC === "many" || barState.recC === "inhibited") ? theme.clockFg : theme.fg
            pillText: barState.recT
            textSize: 16
            onLeftClicked: {
                root.exec.sh("~/.config/rofi/scripts/recorder.sh");
                root.barState.refresh();
            }
            onRightClicked: {
                root.exec.sh("pkill -INT -f gpu-screen-recorder");
                root.barState.refresh();
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 截图
        Pill {
            id: shotPill
            pillId: "shot"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.shotT
            textSize: 16
            onLeftClicked: root.exec.sh("bash " + root.exec.commonDir + "/screenshot.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 取色
        Pill {
            id: pickPill
            pillId: "pick"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.pickT
            textSize: 16
            onLeftClicked: root.exec.sh("bash " + root.exec.commonDir + "/pick-color.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 剪贴板
        Pill {
            id: clipPill
            pillId: "clip"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.clipT
            textSize: 16
            onLeftClicked: root.exec.sh("copyq toggle")
            onRightClicked: root.exec.sh("copyq eval \\\"clear()\\\" 2>/dev/null; notify-send \\\"剪贴板\\\" \\\"已清空\\\"");
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 护眼
        Pill {
            id: gammaPill
            pillId: "gamma"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.gammaT
            textSize: 16
            onLeftClicked: {
                root.exec.sh("bash " + root.exec.commonDir + "/gamma-toggle.sh");
                root.barState.refreshOne("gamma", "bash " + root.exec.commonDir + "/gammastep.sh");
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 主题
        Pill {
            id: themePill
            pillId: "theme"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.themeT
            textSize: 16
            onLeftClicked: {
                root.exec.sh("bash ~/.config/niri/scripts/toggle-theme.sh");
                root.barState.refresh();
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 壁纸
        Pill {
            id: wallPill
            pillId: "wall"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: icons.wallpaper
            textSize: 17
            onLeftClicked: root.uiState.toggleWallpaperPicker(root.screenName)
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 显示器
        Pill {
            id: screenPill
            pillId: "screen"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.screenT
            textSize: 16
            onLeftClicked: {
                root.exec.sh("bash " + root.exec.commonDir + "/screen.sh menu");
                root.barState.refresh();
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
    }

    // 工具胶囊区：按 zoneLayout 渲染槽位（单颗/组合）
    Row {
        id: toolZone
        spacing: 2
        height: 32
        Repeater {
            model: root.zoneReady ? root.zoneLayout : []
            delegate: slotDelegate
        }
    }
}
