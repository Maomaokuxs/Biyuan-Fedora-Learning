import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../components" as Comp
import "." as BarMod

// 顶栏：完整移植 waybar 双屏配置
// 左：launcher workspaces recorder screenshot picker clipboard gammastep theme screen-power music cava mprev mplay mnext lyric
// 右：updates weather pulseaudio brightness/cpu/power-profiles/memory/network/bluetooth/battery/clock/tray/fcitx/inhibit/power
RowLayout {
    id: root
    property var theme
    property var hostWindow: null
    property string screenName: ""
    // HDMI-A-1 用 ddcutil 外接屏亮度，eDP-1 用 waybar brightness.sh
    property bool isExternal: screenName === "HDMI-A-1"
    spacing: 2

    // 整栏一次性淡入：等调色板就位后再现身，避免先以 fallback 色淡入再跳变；
    // 5 秒兜底（无调色板文件时用 fallback 色直接显示）
    property bool paletteTimeout: false
    Timer {
        interval: 5000
        running: true
        onTriggered: root.paletteTimeout = true
    }
    opacity: (Comp.UiState.animReady && (Comp.PaletteState.blob !== "" || root.paletteTimeout)) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // ---------- 胶囊拖拽区（右侧整排 17 个逻辑槽）----------
    // zoneLayout = 有序槽位表，槽位是 id 数组：单元素 = 单颗，多元素 = 组合胶囊。
    // "bri" 是逻辑槽（内接/外接两颗亮度装在 briBox 里领养）；"tray" 固定：
    // 不可拖、不可被合并（命中只给 insert），校验时必须独占单槽恰出现一次。
    // 启动时 FileView 读 qs-bar-layout.json 校验后采用（旧 6-id 格式自动迁移），
    // 拖拽落位即写回。幽灵不在栏内画，状态发布到 UiState 由 shell 覆盖窗渲染。
    property var pillMap: ({})
    property var defaultZoneLayout: [["updates"], ["weather"], ["audio"], ["bri"], ["cpu"], ["pp"], ["mem"], ["net"], ["bt"], ["bat"], ["clock"], ["bell"], ["tray"], ["fcitx"], ["inhibit"], ["cc"], ["power"]]
    property var zoneLayout: defaultZoneLayout
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
        id: layoutFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-layout.json"
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
        root.pillMap = { "updates": updatesPill, "weather": weatherPill, "audio": audioPill, "bri": briBox, "cpu": cpuPill, "pp": ppPill, "mem": memPill, "net": netPill, "bt": btPill, "bat": batPill, "clock": clockPill, "bell": bellPill, "tray": trayBox, "fcitx": fcitxPill, "inhibit": inhibitPill, "cc": ccPill, "power": powerPill };
        console.warn("[pillzone] layout " + JSON.stringify(root.zoneLayout));
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
        var known17 = ["updates", "weather", "audio", "bri", "cpu", "pp", "mem", "net", "bt", "bat", "clock", "bell", "tray", "fcitx", "inhibit", "cc", "power"];
        var known6 = ["cpu", "pp", "mem", "net", "bt", "bat"];
        // 槽位表合法性：数组的数组、槽非空、id 恰好把 known 各覆盖一次
        function validLayout(data, known) {
            if (!Array.isArray(data))
                return false;
            var seen = {};
            for (var i = 0; i < data.length; i++) {
                if (!Array.isArray(data[i]) || data[i].length === 0)
                    return false;
                for (var j = 0; j < data[i].length; j++) {
                    if (typeof data[i][j] !== "string" || known.indexOf(data[i][j]) < 0 || seen[data[i][j]])
                        return false;
                    seen[data[i][j]] = true;
                }
            }
            return Object.keys(seen).length === known.length;
        }
        try {
            var data = JSON.parse(txt);
            if (validLayout(data, known17)) {
                // tray 固定：必须独占单槽
                var trayOk = false;
                for (var i = 0; i < data.length; i++)
                    if (data[i].length === 1 && data[i][0] === "tray")
                        trayOk = true;
                if (!trayOk)
                    return;
                root.zoneLayout = data;
                console.warn("[pillzone] layout " + JSON.stringify(root.zoneLayout));
                return;
            }
            if (validLayout(data, known6)) {
                // 旧 6-id 格式迁移：旧槽位原样替换默认布局中 cpu..bat 的 6 个单颗，
                // 其余槽位用默认单颗补齐，迁移结果回写为新格式。
                var out = [];
                for (var k = 0; k < root.defaultZoneLayout.length; k++) {
                    var s0 = root.defaultZoneLayout[k][0];
                    if (s0 === "cpu") {
                        for (var m = 0; m < data.length; m++)
                            out.push(data[m]);
                    } else if (known6.indexOf(s0) < 0) {
                        out.push(root.defaultZoneLayout[k]);
                    }
                }
                root.zoneLayout = out;
                console.warn("[pillzone] layout " + JSON.stringify(root.zoneLayout));
                Comp.Exec.sh("printf '%s' '" + JSON.stringify(out).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout.json");
                return;
            }
        } catch (e) {
            return;
        }
    }
    // 布局变更前把所有 pill 送回仓库，避免 Repeater 重建 delegate 时连带销毁
    function rescueAllPills() {
        for (var i = 0; i < root.slotItems.length; i++) {
            var s = root.slotItems[i];
            if (!s)
                continue;
            for (var j = 0; j < s.members.length; j++) {
                s.members[j].bare = false;
                s.members[j].parent = pillWarehouse;
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
            Comp.UiState.dragText = pill.pillText;
            Comp.UiState.dragBg = pill.normalBg;
            Comp.UiState.dragFg = pill.normalFg;
            Comp.UiState.dragW = Math.max(pill.width, 40);
            Comp.UiState.dragX = ap.x + pill.width / 2;
            Comp.UiState.dragY = ap.y + 16;
        }
        Comp.UiState.dragScreen = root.screenName;
        Comp.UiState.dragActive = true;
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
    }
    function pillDragMoved(wx, wy) {
        if (root.dragId === "")
            return;
        Comp.UiState.dragX = wx;
        Comp.UiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var winW = root.hostWindow ? root.hostWindow.width : 100000;
        var inBar = wx >= 0 && wx <= winW && wy >= -12 && wy <= 58;
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
                    var slotIdsI = root.zoneLayout[i];
                    var isTraySlot = slotIdsI && slotIdsI.length === 1 && slotIdsI[0] === "tray";
                    if (isTraySlot) {
                        // tray 固定：不可被合并，命中只给左右 insert
                        if (fx < 0.5) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                        else { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    }
                    else if (fx < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fx > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(pillZone);
                if (wx >= zp.x - 10 && wx <= zp.x + pillZone.width + 10 && wy >= zp.y - 8 && wy <= zp.y + pillZone.height + 8) {
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
        Comp.UiState.dragActive = false;
        var pid = root.dragId;
        if (pid === "")
            return;
        if (root.dragEnding) {
            console.warn("[pillzone] dragEnd reentry blocked " + pid);
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
        // 兜底：merge 目标若是 tray 单槽，改成插到 tray 之后（Moved 已拦截，这里防漏）
        if (type === "merge" && t >= 0 && t < root.zoneLayout.length) {
            var ts = root.zoneLayout[t];
            if (ts.length === 1 && ts[0] === "tray") {
                type = "insert";
                t = t + 1;
            }
        }
        if (type === "merge" && t === from) {
            root.dragEnding = false;
            return;
        }
        var layout = root.zoneLayout.map(function(a) { return a.slice(); });
        var fromArr = layout[from];
        var fix = fromArr.indexOf(pid);
        if (fix < 0) {
            console.warn("[pillzone] dragEnd abort: " + pid + " not in slot " + from);
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
            console.warn("[pillzone] dragEnd noop " + pid);
            root.dragEnding = false;
            return;
        }
        root.rescueAllPills();
        root.zoneLayout = layout;
        // 落位自检（取证）：重建后仍滞留仓库的 pill 说明被竞态吞了，打日志留证
        Qt.callLater(function() {
            for (var oid in root.pillMap) {
                var op = root.pillMap[oid];
                if (op && op.parent === pillWarehouse)
                    console.warn("[pillzone] orphan " + oid);
            }
        });
        console.warn("[pillzone] layout " + JSON.stringify(layout));
        Comp.Exec.sh("printf '%s' '" + JSON.stringify(layout).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout.json");
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
                    members[i].parent = pillWarehouse;
                }
                root.unregisterSlot(index, slot);
            }
        }
    }

    // 显隐开关走 BarState 单相位（flag 与文本同一次产出，动画单波齐出）

    // ---------- 左组 ----------
    Comp.Pill {
        normalBg: theme.frameBg; normalFg: theme.fg
        pillText: Comp.Icons.launcher; textSize: 18
        clickLeft: "rofi -show drun"
        clickRight: "bash " + Comp.Exec.commonDir + "/toggle-left.sh"
    }
    BarMod.Workspaces { theme: root.theme; screenName: root.screenName }

    // 左侧工具组：8 图标合并到一个胶囊（录制/截图/取色/剪贴板/护眼/主题/壁纸/显示器）
    Comp.ToolsGroup {
        theme: root.theme
        screenName: root.screenName
        forceHidden: Comp.BarState.flagL
        barState: Comp.BarState
        exec: Comp.Exec
        uiState: Comp.UiState
        icons: Comp.Icons
    }

    // 媒体组（原生 Mpris，语义与 music.py / mpris 控制一致）
    Comp.MusicInfo {
        normalBg: theme.mediaBg; normalFg: theme.fg
        theme: root.theme; screenName: root.screenName
        // 右键：音乐总开关，隐藏音律+歌词（与歌词右键一致）
        onRightClicked: {
            Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music.sh");
            Comp.BarState.refresh();
        }
    }
    BarMod.LevelMeter { theme: root.theme; screenName: root.screenName }
    Comp.Pill {
        normalBg: theme.mediaBg; normalFg: theme.fg
        pillText: Comp.BarState.lyricT
        // 音乐组跟随者：总闸或尾闸拉下都折叠（开关位在歌名/音律右键）
        forceHidden: Comp.BarState.flagM || Comp.BarState.flagT
        // 右键：音乐总开关（与歌名右键一致，含音律），点后即时补刷
        onRightClicked: {
            Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music.sh");
            Comp.BarState.refresh();
        }
    }

    Item {
        id: barSpacer
        Layout.fillWidth: true
        // 字形预热文本挂在这里：Item 的孩子不参与 RowLayout 排布
        // （之前直接放 Bar 里，implicitWidth 巨大把整栏顶偏），
        // 但仍会渲染，保证图标字形首帧前传好。
        Text {
            width: 1; height: 1
            opacity: 0.01
            clip: true
            font.family: theme.fontFamily
            font.pixelSize: 14
            text: Comp.Icons.launcher + Comp.Icons.power
                + Comp.Icons.musicPlaying + Comp.Icons.musicPaused
                + Comp.Icons.prev + Comp.Icons.play + Comp.Icons.pause + Comp.Icons.next
                + Comp.Icons.shuffle + Comp.Icons.loopOff + Comp.Icons.loopAll + Comp.Icons.loopOne
                + Comp.Icons.volMute + Comp.Icons.vol0 + Comp.Icons.volLow + Comp.Icons.volHigh
                + Comp.Icons.briLow + Comp.Icons.briMid + Comp.Icons.briHigh
                + Comp.Icons.cpu + Comp.Icons.mem + Comp.Icons.net
                + Comp.Icons.btOn + Comp.Icons.btOff
                + Comp.Icons.bat0 + Comp.Icons.bat1 + Comp.Icons.bat2 + Comp.Icons.bat3 + Comp.Icons.bat4
                + Comp.Icons.batCharging + Comp.Icons.coverFallback
        }
        // 拖拽幽灵已移交 shell 层覆盖窗（UiState.drag* 状态驱动），栏内不再绘制
    }

    // ---------- 右组 ----------
    // 胶囊仓库：右侧全部胶囊声明停在这里（隐藏不排版），由 pillZone 槽位按
    // zoneLayout 领养渲染。声明内部绑定与原来一字未改，只加 id/pillId/
    // dragEnabled 与拖拽信号连接（tray 是内联 Rectangle 不是 Pill 家族，
    // 不加拖拽、只被领养占位）。亮度两颗装进 briBox 逻辑槽（见下）。
    Item {
        id: pillWarehouse
        visible: false
        width: 0
        height: 0
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0

        Comp.ScriptPill {
            id: updatesPill
            pillId: "updates"
            dragEnabled: true
            baseBg: theme.accent; baseFg: theme.fg; hiBg: theme.clockBg; hiFg: theme.clockFg
            execCmd: Comp.Exec.commonDir + "/check-updates.sh"
            pollInterval: 3600000
            clickLeft: "kitty --hold sh -c 'sudo dnf upgrade'"
            clickRight: "pkill -RTMIN+8 waybar"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.ScriptPill {
            id: weatherPill
            pillId: "weather"
            dragEnabled: true
            baseBg: theme.accent; baseFg: theme.fg
            execCmd: Comp.Exec.commonDir + "/weather.py"
            pollInterval: 1800000
            clickLeft: "kitty --hold curl wttr.in"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.AudioPill {
            id: audioPill
            pillId: "audio"
            dragEnabled: true
            baseBg: theme.deviceBg; baseFg: theme.fg
            screenName: root.screenName
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 亮度逻辑槽：内接屏亮度走共享聚合；外接屏 ddc 太慢，独立 ScriptPill 保留。
        // 两块互斥显示（forceHidden），同报一个 briAnchorX（隐藏的不上报）。
        // briBox 本体被槽位领养：animW 取两颗较大值（任一时刻只有一颗可见），
        // pillText/normalBg/normalFg 转发可见的那颗，供幽灵与组背景读取；
        // 两颗 pillId 同为 "bri"，隐藏的那颗没面积自然抓不到。
        Item {
            id: briBox
            height: 32
            // 与 Pill 对齐的哑属性：槽位领养/营救会统一写 bare、组内统一绑 bareFg，
            // 缺了会报 Cannot assign 并中断 delegate 的 onCompleted（成员登记失效变空白）
            property bool bare: false
            property color bareFg: normalFg
            property real animW: Math.max(briIntPill.animW, briExtPill.animW)
            width: animW
            property bool shown: briIntPill.shown || briExtPill.shown
            property string pillText: root.isExternal ? briExtPill.pillText : briIntPill.pillText
            property color normalBg: theme.deviceBg
            property color normalFg: theme.fg

            Comp.Pill {
                id: briIntPill
                pillId: "bri"
                dragEnabled: true
                normalBg: theme.deviceBg; normalFg: theme.fg
                anchorKey: "briAnchorX"
                anchorScreen: root.screenName
                forceHidden: root.isExternal
                pillText: Comp.BarState.briT
                scrollUpCmd: Comp.Exec.scriptDir + "/brightness.sh up"
                scrollDownCmd: Comp.Exec.scriptDir + "/brightness.sh down"
                clickRight: Comp.Exec.scriptDir + "/brightness.sh mid"
                onLeftClicked: { Comp.UiState.toggleBri(root.screenName, root.isExternal); Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh"); }
                onRightClicked: Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh")
                onScrollUp: Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh")
                onScrollDown: Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh")
                onDragStarted: pid => root.pillDragStart(pid)
                onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
                onDragEnded: root.pillDragEnd()
            }
            Comp.ScriptPill {
                id: briExtPill
                pillId: "bri"
                dragEnabled: true
                baseBg: theme.deviceBg; baseFg: theme.fg
                anchorKey: "briAnchorX"
                anchorScreen: root.screenName
                forceHidden: !root.isExternal
                execCmd: "bash " + Comp.Exec.scriptDir + "/brightness-external.sh"
                pollInterval: 30000
                scrollUpCmd: "ddcutil setvcp 10 + 5"
                scrollDownCmd: "ddcutil setvcp 10 - 5"
                clickRight: "ddcutil setvcp 10 50"
                onLeftClicked: Comp.UiState.toggleBri(root.screenName, root.isExternal)
                onDragStarted: pid => root.pillDragStart(pid)
                onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
                onDragEnded: root.pillDragEnd()
            }
        }
        Comp.Pill {
            id: cpuPill
            pillId: "cpu"
            dragEnabled: true
            normalBg: theme.sysmonBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            pillText: Comp.BarState.cpuT
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: ppPill
            pillId: "pp"
            dragEnabled: true
            normalFg: (Comp.BarState.ppC === "recording" || Comp.BarState.ppC === "kernel" || Comp.BarState.ppC === "many" || Comp.BarState.ppC === "inhibited") ? theme.clockFg : theme.fg
            normalBg: (Comp.BarState.ppC === "recording" || Comp.BarState.ppC === "kernel" || Comp.BarState.ppC === "many" || Comp.BarState.ppC === "inhibited") ? theme.clockBg : theme.sysmonBg
            pillText: Comp.BarState.ppT
            clickLeft: Comp.Exec.commonDir + "/powerprofiles.sh toggle"
            onLeftClicked: Comp.BarState.refreshOne("pp", Comp.Exec.commonDir + "/powerprofiles.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: memPill
            pillId: "mem"
            dragEnabled: true
            normalBg: theme.sysmonBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            pillText: Comp.BarState.memT
            clickLeft: "kitty --title 'System Monitor' btop"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: netPill
            pillId: "net"
            dragEnabled: true
            normalBg: theme.deviceBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            pillText: Comp.BarState.netT
            clickLeft: "kitty -e nmtui"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.BluetoothPill {
            id: btPill
            pillId: "bt"
            dragEnabled: true
            normalBg: theme.deviceBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.BatteryPill {
            id: batPill
            pillId: "bat"
            dragEnabled: true
            normalBg: theme.sysmonBg; normalFg: theme.fg
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 时钟：反色锚点
        Comp.Pill {
            id: clockPill
            pillId: "clock"
            dragEnabled: true
            normalBg: theme.clockBg; normalFg: theme.clockFg; bold: true
            pillText: Qt.formatDateTime(clockDate, "hh:mm")
            property var clockDate: new Date()
            Timer { interval: 1000; running: true; repeat: true; onTriggered: clockPill.clockDate = new Date() }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 通知铃：未读数 + 开关历史中心。无通知时用 0 占位，宽度恒定，浮窗不跳。
        // anchorKey 上报中心横坐标，toast 栈与通知中心都锚到铃铛下方
        //（缺了它 notifAnchorX 恒为 0，toast 窗会被摆到屏外——2026-09 实测）。
        Comp.Pill {
            id: bellPill
            pillId: "bell"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            anchorKey: "notifAnchorX"
            anchorScreen: root.screenName
            pillText: Comp.Icons.bell + " " + Comp.Notifs.unread
            onLeftClicked: {
                Comp.Notifs.markRead();
                Comp.UiState.toggleNotif(root.screenName);
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 托盘：与其他模块一致的圆角色块底。
        // 注意：items 是 UntypedObjectModel，没有 .count，Repeater 直接吃它也没有
        // modelData；一律走 .values（JS 数组），和 Mpris 用法一致。
        Rectangle {
            id: trayBox
            // 同 briBox：槽位领养/营救统一写 bare，缺属性会中断 delegate 完成
            property bool bare: false
            property real animW: SystemTray.items.values.length > 0 ? trayRow.implicitWidth + 12 : 0
            // shell 单引号转义（歌名里什么引号都有）
            function shQ(s) {
                return "'" + String(s || "").replace(/'/g, "'\\''") + "'";
            }

            Behavior on animW { enabled: Comp.UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: Comp.UiState.animReady; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            visible: opacity > 0.01
            opacity: SystemTray.items.values.length > 0 ? 1 : 0
            height: 32
            width: trayRow.implicitWidth + 12
            Layout.preferredWidth: animW
            Layout.preferredHeight: 32
            radius: 10
            clip: true
            color: theme.accent

            Row {
                id: trayRow
                anchors.centerIn: parent
                spacing: 4
                Repeater {
                    model: SystemTray.items.values
                    MouseArea {
                        id: trayMouse
                        width: 24; height: 32
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // 左键通用链（零应用名）：onlyMenu 出菜单，否则走 tray-open.py——
                        // 模糊找窗聚焦（已聚焦跳过）→ 调 Activate（缺失则报错）→
                        // 触发菜单显示项 → SecondaryActivate。右键一律菜单优先。
                        onClicked: e => {
                            if (e.button === Qt.LeftButton) {
                                if (modelData.onlyMenu && modelData.hasMenu) {
                                    trayMenu.open();
                                } else {
                                    Comp.Exec.sh("python3 " + Comp.Exec.commonDir + "/tray-open.py " + trayBox.shQ(modelData.id) + " " + trayBox.shQ(modelData.title) + " " + trayBox.shQ(modelData.tooltipTitle));
                                }
                            } else {
                                if (modelData.hasMenu)
                                    trayMenu.open();
                                else
                                    modelData.secondaryActivate();
                            }
                        }
                        // 右键菜单：很多 SNI 不实现 SecondaryActivate，
                        // 必须走 DBusMenu；anchor.window 复用顶栏窗口
                        QsMenuAnchor {
                            id: trayMenu
                            anchor.window: root.hostWindow
                            anchor.item: trayMouse
                            anchor.edges: Edges.Bottom
                            anchor.gravity: Edges.Bottom
                            menu: modelData.menu
                        }
                        // tray 图标可能是主题名也可能是路径，必须用 IconImage，
                        // 普通 Image 播不了主题名会导致整块空白
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 20
                            source: modelData.icon
                        }
                    }
                }
            }
        }
        Comp.ScriptPill {
            id: fcitxPill
            pillId: "fcitx"
            dragEnabled: true
            baseBg: theme.accent; baseFg: theme.fg
            execCmd: Comp.Exec.commonDir + "/fcitx_status.sh"
            pollInterval: 1000
            clickLeft: "fcitx5-remote -s"
            clickRight: "fcitx5-configtool"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: inhibitPill
            pillId: "inhibit"
            dragEnabled: true
            normalBg: (Comp.BarState.inhibitC === "recording" || Comp.BarState.inhibitC === "kernel" || Comp.BarState.inhibitC === "many" || Comp.BarState.inhibitC === "inhibited") ? theme.clockBg : theme.accent
            normalFg: (Comp.BarState.inhibitC === "recording" || Comp.BarState.inhibitC === "kernel" || Comp.BarState.inhibitC === "many" || Comp.BarState.inhibitC === "inhibited") ? theme.clockFg : theme.fg
            pillText: Comp.BarState.inhibitT
            clickLeft: "bash " + Comp.Exec.commonDir + "/inhibit.sh toggle"
            onLeftClicked: Comp.BarState.refreshOne("inhibit", "bash " + Comp.Exec.scriptDir + "/inhibit.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: ccPill
            pillId: "cc"
            dragEnabled: true
            normalBg: theme.frameBg; normalFg: theme.fg
            anchorKey: "ccAnchorX"
            anchorScreen: root.screenName
            pillText: Comp.Icons.sliders
            textSize: 15
            onLeftClicked: Comp.UiState.toggleSidebar(root.screenName)
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: powerPill
            pillId: "power"
            dragEnabled: true
            normalBg: theme.frameBg; normalFg: theme.fg
            pillText: Comp.Icons.power
            clickLeft: "~/.config/rofi/scripts/powermenu.sh"
            clickRight: "bash " + Comp.Exec.commonDir + "/toggle-system.sh"
            onRightClicked: Comp.BarState.refresh()
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
    }
    // 天气缓存（--fetch/唤醒预热）一落地就补刷，不等 30 分钟轮询；
    // 前台 exec 从不写盘，不会自激循环
    FileView {
        path: Quickshell.env("HOME") + "/.cache/by-mgr/weather.json"
        watchChanges: true
        onFileChanged: weatherPill.refresh()
    }
    // 胶囊区：按 zoneLayout 渲染槽位（单颗/组合），槽位 delegate 在文件上方 slotDelegate
    Row {
        id: pillZone
        spacing: 2
        height: 32
        Repeater {
            model: root.zoneReady ? root.zoneLayout : []
            delegate: slotDelegate
        }
    }
}
