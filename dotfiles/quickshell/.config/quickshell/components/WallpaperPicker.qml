import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// 壁纸选择器：左大预览 + 可拖竖线 + 右缩略图网格（1~3 列随宽） + 下配色预览。
// 竖线可拖：往左拖网格变宽、列数变多，拖到 0 预览消失变纯网格；位置持久化到 ~/.cache/by-mgr/qs-picker-split。
// 外壳 900×600 居中，背景 Theme.bg（跟随配色，不全屏、不透明窗、不写死深棕）。
// 顶栏只留标题 + ✕。无过渡面板、无收藏/随机/应用主按钮、无上一下张、无徽标/说明。
// 过渡用原来默认 awww --transition-type random，UI 不选。
// 动效：切图时仅左侧大预览做滑入 + 斜切擦除（和角色立绘登场同一节奏）。
// 实现：旧图底层不动；新图用 Canvas 做斜切 discard（此环境 ShaderEffect 不渲染）——
// 斜切边左侧显示新图（采样 x 随 t 左移归位 = 滑入），右侧 discard 露出底层旧图；
// 左上梯形起帧已揭示，斜切边随 progress 从左往右扫。硬边缘，无渐变带，全程不碰 opacity。
// Canvas 2D 路径（ShaderEffect 在此环境静默不渲染），不用 Y 轴翻页，不用淡入。
// 新图 Ready 才开动画（避免异步未加载时纹理为空、动画白跑），超时 800ms 直接显示。
// 右侧选图列与下方配色不动，不晃。回车应用播 awww 真过渡。原 WallpaperCard/ControlCenter 全部保留。
Item {
    id: root
    property var theme
    signal requestClose

    property var wallFiles: []
    property string current: ""
    property int selectedIndex: -1
    property real wheelAcc: 0
    property double lastWheelMs: 0
    property bool pickerOpen: UiState.wallpaperPickerOpen
    property double lastSwitchMs: 0
    // 每个壁纸的信息：name -> {w, h, size}，由 infoProc 批量 file+stat 填充，失败则只显示名字
    property var infoMap: ({})

    // 可拖竖线：左侧预览区宽度（-1 = 未初始化用默认）；splitEff 为钳制后的生效值
    property real splitW: -1
    readonly property real splitMax: Math.max(0, mainArea.width - 232)
    readonly property real splitEff: root.splitW < 0 ? Math.max(0, mainArea.width - 240) : Math.max(0, Math.min(root.splitW, root.splitMax))

    // 配色预览（跟随选中壁纸，不读 global-palette.env）：空 = 未算出，UI 回落 Theme 色
    property var previewPalette: ({})
    property var paletteCache: ({})
    property string paletteWantKey: ""
    property string paletteWantSmall: ""
    property string paletteWantOrig: ""
    property string paletteBusyKey: ""

    function shQuote(s) {
        return "'" + String(s || "").replace(/'/g, "'\"'\"'") + "'";
    }
    function saveSplit() {
        Exec.sh("printf '%s' " + Math.round(root.splitEff) + " > ~/.cache/by-mgr/qs-picker-split");
    }
    function filePath(url) {
        return String(url || "").replace(/^file:\/\//, "");
    }
    function wallBase(url) {
        var s = String(url || "");
        var i = s.lastIndexOf("/");
        return i >= 0 ? s.slice(i + 1) : s;
    }
    function isCurrent(url) {
        var u = String(url || "");
        return ("file://" + root.current === u) || (root.current === u.replace(/^file:\/\//, ""));
    }
    function selectedItem() {
        if (root.selectedIndex >= 0 && root.selectedIndex < root.wallFiles.length)
            return root.wallFiles[root.selectedIndex];
        return null;
    }
    function displayItem() {
        return root.selectedItem();
    }
    function displayUrl() {
        var it = root.selectedItem();
        return it ? String(it.url || "") : "";
    }
    function formatSize(bytes) {
        if (!bytes || bytes <= 0) return "";
        if (bytes >= 1048576) return (bytes / 1048576).toFixed(1) + " MB";
        if (bytes >= 1024) return Math.round(bytes / 1024) + " KB";
        return bytes + " B";
    }
    function infoTextFor(idx) {
        if (idx < 0 || idx >= root.wallFiles.length) return "";
        var it = root.wallFiles[idx];
        var info = root.infoMap[it.name];
        var parts = [];
        if (info) {
            if (info.w && info.h) parts.push(info.w + "×" + info.h);
            if (info.size) parts.push(root.formatSize(info.size));
        }
        return parts.join(" · ");
    }
    function stepSelection(d) {
        if (root.wallFiles.length === 0) return;
        var n = root.wallFiles.length;
        root.selectedIndex = (((root.selectedIndex + d) % n) + n) % n;
        root.requestPalette(root.selectedItem());
        preview.show(root.displayUrl(), true);
    }
    function tryStep(d) {
        var now = Date.now();
        if (now - root.lastSwitchMs < 120) return;
        root.lastSwitchMs = now;
        root.stepSelection(d);
    }
    function trySelect(idx) {
        var now = Date.now();
        if (now - root.lastSwitchMs < 120) return;
        var n = root.wallFiles.length;
        if (n <= 0 || idx < 0 || idx >= n) return;
        if (idx === root.selectedIndex) return;
        root.lastSwitchMs = now;
        root.selectedIndex = idx;
        root.requestPalette(root.selectedItem());
        preview.show(root.displayUrl(), true);
    }
    function refreshAll() {
        root.wallFiles = [];
        root.infoMap = {};
        root.selectedIndex = -1;
        lsProc.running = true;
        curProc.running = true;
    }
    function snapToCurrent() {
        if (root.wallFiles.length === 0) return;
        if (root.current !== "") {
            for (var i = 0; i < root.wallFiles.length; i++) {
                if (root.isCurrent(root.wallFiles[i].url)) {
                    root.selectedIndex = i;
                    preview.setDirect(String(root.wallFiles[i].url || ""));
                    infoProc.running = true;
                    root.requestPalette(root.selectedItem());
                    return;
                }
            }
        }
        if (root.selectedIndex < 0) root.selectedIndex = 0;
        var first = root.selectedItem();
        if (first) {
            preview.setDirect(String(first.url || ""));
        }
        infoProc.running = true;
        root.requestPalette(root.selectedItem());
    }
    function applySelected() {
        var it = root.selectedItem();
        if (!it) return;
        var p = root.filePath(it.url);
        var q = root.shQuote(p);
        // 原来默认：awww random + theme-sync --no-render（仅同步配色，不双渲染）
        Exec.sh("awww img " + q + " --transition-type random --transition-pos center --transition-duration 2; bash ~/.config/niri/scripts/theme-sync.sh --no-render " + q + "; notify-send \"壁纸已更换\" " + root.shQuote(root.wallBase(it.url)) + " -i " + q);
        root.current = p;
        root.requestClose();
    }
    // 取色缓存键：thumbHd 文件名即 wallthumbs 的 stat id（%d-%i-%s-%Y，含 mtime），文件一变键就变
    function paletteKeyFor(item) {
        if (!item) return "";
        return root.wallBase(String(item.thumbHd || item.thumb || item.url || ""));
    }
    function palHex(kind) {
        var p = root.previewPalette;
        if (p && p[kind]) return p[kind];
        return root.theme[kind];
    }
    // 选中哪张就算哪张的 hellwal 四色：hellwal -j 只输出 JSON、跳过模板，不应用壁纸、不写 global-palette.env。
    // 不传 -v（不反色），默认深色：BG 深色、FG 浅色、ACCENT 主色、MUTED 低饱和同系色。
    function requestPalette(item) {
        if (!item) return;
        var key = root.paletteKeyFor(item);
        if (key === "") return;
        var hit = root.paletteCache[key];
        if (hit) { root.previewPalette = hit; return; }
        root.paletteWantKey = key;
        root.paletteWantSmall = root.filePath(String(item.thumbHd || item.thumb || item.url || ""));
        root.paletteWantOrig = root.filePath(String(item.url || ""));
        if (!paletteProc.running) root.startPalette();
    }
    function startPalette() {
        root.paletteBusyKey = root.paletteWantKey;
        var small = root.paletteWantSmall;
        var orig = root.paletteWantOrig;
        // 回落链（复用 theme-sync 思路）：HD 缩略图 -> 原图 -> ffmpeg 转 png 再取；只取 JSON，不落地
        var script = "J=$(hellwal --no-cache --skip-term-colors -i " + root.shQuote(small) + " -j 2>/dev/null); " +
            "if [ -z \"$J\" ]; then J=$(hellwal --no-cache --skip-term-colors -i " + root.shQuote(orig) + " -j 2>/dev/null); fi; " +
            "if [ -z \"$J\" ]; then T=$(mktemp /tmp/by-mgr-pal-XXXXXX.png); " +
            "if timeout 30 ffmpeg -y -loglevel error -i " + root.shQuote(orig) + " -frames:v 1 \"$T\" 2>/dev/null && [ -s \"$T\" ]; then " +
            "J=$(hellwal --no-cache --skip-term-colors -i \"$T\" -j 2>/dev/null); fi; rm -f \"$T\"; fi; " +
            "printf '%s' \"$J\"";
        paletteProc.command = ["bash", "-c", script];
        paletteProc.running = true;
    }
    function applyPaletteJson(text, key) {
        if (!text || key === "") return;
        try {
            var j = JSON.parse(text);
            var sp = j.special || {};
            var co = j.colors || {};
            var bg = String(sp.background || co.color0 || "#1e1e2e");
            var fg = String(sp.foreground || co.color15 || "#ffffff");
            var ac = String(co.color4 || "#89b4fa");
            var mu = String(co.color8 || co.color0 || "#45475a");
            if (bg === "#000000" || bg === "#111111") bg = "#1e1e2e";
            if (mu === "#000000" || mu === "#111111") mu = "#2a2b3c";
            var res = { bg: bg, fg: fg, accent: ac, muted: mu };
            var m = Object.assign({}, root.paletteCache);
            m[key] = res;
            root.paletteCache = m;
            // 只接受当前选中的结果，旧请求后到不覆盖新选中
            if (key === root.paletteKeyFor(root.selectedItem()))
                root.previewPalette = res;
        } catch (e) {}
    }
    function copyColor(hex, label) {
        var q = root.shQuote(String(hex || ""));
        Exec.sh("printf '%s' " + q + " | wl-copy; notify-send \"已复制色值\" " + root.shQuote(label + " " + hex));
    }
    onPickerOpenChanged: {
        if (root.pickerOpen) {
            root.refreshAll();
            root.forceActiveFocus();
        }
    }
    Component.onCompleted: {
        root.refreshAll();
        splitProc.running = true;
    }

    Process {
        id: lsProc
        command: ["bash", "-c", "bash " + Exec.scriptDir + "/wallthumbs.sh list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var j = JSON.parse(data);
                    if (j.name && j.url)
                        root.wallFiles = root.wallFiles.concat([{ name: j.name, url: j.url, thumb: j.thumb || j.url, thumbHd: j.thumbHd || j.thumb || j.url }]);
                } catch (e) {}
            }
        }
        onRunningChanged: { if (!lsProc.running) root.snapToCurrent(); }
    }
    Process {
        id: curProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/last-wallpaper 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { root.current = this.text.trim(); root.snapToCurrent(); }
        }
    }
    // 上次拖拽的竖线位置（整数 px）：读到合法值才用（splitEff 负责钳制到当前窗口范围），否则 splitW 保持 -1 用默认
    Process {
        id: splitProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/qs-picker-split 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var v = parseInt(this.text.trim(), 10);
                if (!isNaN(v) && v >= 0) root.splitW = v;
            }
        }
    }
    // 批量取分辨率 + 大小：find + file + stat，一次输出 name|w|h|size
    Process {
        id: infoProc
        command: ["bash", "-c", "find ~/Pictures/wallpapers -maxdepth 1 -type f -print0 2>/dev/null | while IFS= read -r -d '' f; do b=$(basename \"$f\"); dim=$(identify -format %wx%h \"$f\" 2>/dev/null || file -b \"$f\" 2>/dev/null | grep -oE '[0-9]+ ?x ?[0-9]+' | tail -1 | sed -E 's/([0-9]+) ?x ?([0-9]+)/\\1 x \\2/'); sz=$(stat -c %s \"$f\" 2>/dev/null); echo \"$b|$dim|$sz\"; done"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var parts = String(data).split("|");
                if (parts.length < 3) return;
                var nm = parts[0];
                var dimParts = String(parts[1] || "").split(/ ?x ?/);
                var m = Object.assign({}, root.infoMap);
                m[nm] = { w: parseInt(dimParts[0] || "0", 10) || 0, h: parseInt(dimParts[1] || "0", 10) || 0, size: parseInt(parts[2] || "0", 10) || 0 };
                root.infoMap = m;
            }
        }
    }

    // 选中壁纸的 hellwal 取色（只取 JSON 预览，不应用、不写 global-palette.env）
    Process {
        id: paletteProc
        stdout: StdioCollector {
            onStreamFinished: {
                var key = root.paletteBusyKey;
                root.applyPaletteJson(this.text, key);
                // 切图期间有更新的请求排队时，接着算下一个；已缓存的直接用，不重跑
                if (root.paletteWantKey !== "" && root.paletteWantKey !== key && !root.paletteCache[root.paletteWantKey])
                    root.startPalette();
            }
        }
    }

    focus: true
    Keys.onPressed: (event) => {
        if (event.key === Qt.Key_Left) {
            root.tryStep(-1); event.accepted = true;
        } else if (event.key === Qt.Key_Right) {
            root.tryStep(1); event.accepted = true;
        } else if (event.key === Qt.Key_Up) {
            root.tryStep(-grid.cols); event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            root.tryStep(grid.cols); event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter || event.key === Qt.Key_Space) {
            root.applySelected(); event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.requestClose(); event.accepted = true;
        }
    }
    WheelHandler {
        onWheel: (event) => {
            var d = event.angleDelta.y !== 0 ? event.angleDelta.y : event.pixelDelta.y;
            root.wheelAcc += d;
            var now = Date.now();
            if (now - root.lastWheelMs < 120) { event.accepted = true; return; }
            if (Math.abs(root.wheelAcc) >= 40) {
                if (root.wheelAcc < 0) root.tryStep(1); else root.tryStep(-1);
                root.wheelAcc = 0;
                root.lastWheelMs = now;
            }
            event.accepted = true;
        }
    }

    // 外壳：Theme.bg，radius 16
    ClippingRectangle {
        anchors.fill: parent
        radius: 16
        color: root.theme.bg
        border.color: Qt.alpha(root.theme.muted, 0.35)
        border.width: 1

        // 顶栏：标题 + ✕
        Item {
            id: header
            anchors { top: parent.top; left: parent.left; right: parent.right }
            anchors.leftMargin: 16; anchors.rightMargin: 16
            height: 48
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "SELECT WALLPAPER"
                font.family: root.theme.fontFamily; font.pixelSize: 16; font.bold: true; color: root.theme.fg
            }
            Item {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                width: 28; height: 28
                Text {
                    anchors.centerIn: parent
                    text: "✕"
                    font.family: root.theme.fontFamily; font.pixelSize: 14; color: root.theme.fg
                }
                MouseArea { anchors.fill: parent; onClicked: root.requestClose() }
            }
        }

        // 主区：左大预览 + 右选图列
        Item {
            id: mainArea
            anchors { top: header.bottom; left: parent.left; right: parent.right; bottom: paletteBar.top }
            anchors.leftMargin: 16; anchors.rightMargin: 16; anchors.topMargin: 4; anchors.bottomMargin: 8

            // 左：大预览 + 名字 + 信息（宽度 = splitEff，竖线拖到 0 时整体隐藏）
            Item {
                id: previewArea
                anchors { top: parent.top; left: parent.left; bottom: parent.bottom }
                width: root.splitEff
                visible: root.splitEff > 0
                clip: true

                // 大预览：UI 与动效隔离（WallpaperPreview 组件），左→右裁剪揭示
                Item {
                    id: flipWrap
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: root.splitEff >= 200 ? parent.height - 52 : parent.height
                    clip: true

                    // 轻阴影（在预览卡后，静态，非动画）
                    Rectangle {
                        anchors.fill: parent
                        anchors.topMargin: 6
                        radius: 12; color: "black"; opacity: 0.12
                    }
                    WallpaperPreview {
                        id: preview
                        anchors.fill: parent
                        bgColor: root.theme.mediaBg
                    }
                }

                Text {
                    id: previewName
                    anchors { top: flipWrap.bottom; left: parent.left; right: parent.right }
                    anchors.topMargin: 8
                    visible: root.splitEff >= 200
                    text: {
                        var it = root.displayItem();
                        return it ? it.name : "";
                    }
                    font.family: root.theme.fontFamily; font.pixelSize: 18; font.bold: true; color: root.theme.fg
                    elide: Text.ElideRight
                }
                Text {
                    anchors { top: previewName.bottom; left: parent.left; right: parent.right }
                    anchors.topMargin: 2
                    visible: root.splitEff >= 200
                    text: root.infoTextFor(root.selectedIndex)
                    font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.muted
                    elide: Text.ElideRight
                }
            }

            // 右：壁纸缩略图网格（列数随自身宽度：<360 一列 / <660 两列 / 否则三列）
            Item {
                id: gridArea
                anchors { top: parent.top; bottom: parent.bottom }
                x: root.splitEff + 24
                width: parent.width - root.splitEff - 24

                GridView {
                    id: grid
                    anchors.fill: parent
                    clip: true
                    model: root.wallFiles
                    currentIndex: root.selectedIndex
                    highlightFollowsCurrentItem: true
                    readonly property int cols: width < 360 ? 1 : (width < 660 ? 2 : 3)
                    cellWidth: Math.floor(width / cols)
                    cellHeight: Math.round((cellWidth - 12) * 9 / 16 + 12)
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        // 缩略图：小图用 thumb（已够），不放大
                        ClippingRectangle {
                            anchors.fill: parent
                            anchors.margins: 6
                            radius: 8
                            color: root.theme.mediaBg
                            border.width: (index === root.selectedIndex) ? 3 : 0
                            border.color: root.theme.fg
                            Behavior on border.width { NumberAnimation { duration: 150 } }
                            Image {
                                anchors.fill: parent
                                source: String(modelData.thumb || modelData.url || "")
                                sourceSize.width: 440; sourceSize.height: 176
                                asynchronous: true; cache: true; smooth: true; mipmap: true
                                fillMode: Image.PreserveAspectCrop
                            }
                            Text {
                                anchors { right: parent.right; bottom: parent.bottom }
                                anchors.margins: 6
                                text: root.isCurrent(modelData.url) ? "使用中" : ""
                                font.family: root.theme.fontFamily; font.pixelSize: 10; font.bold: true; color: "white"
                                visible: root.isCurrent(modelData.url)
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.trySelect(index)
                        }
                    }
                    onCurrentIndexChanged: {
                        if (currentIndex >= 0) positionViewAtIndex(currentIndex, GridView.Contain);
                    }
                }
            }

            // 中：可拖拽竖线（线居预览/列表空隙正中 splitEff+12；热区 14px 以线为中心）
            Item {
                id: divider
                x: root.splitEff + 2
                width: 20
                anchors { top: parent.top; bottom: parent.bottom }

                Rectangle {
                    anchors { top: parent.top; bottom: parent.bottom }
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 2
                    color: Qt.alpha(root.theme.muted, 0.35)
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 6; height: 36; radius: 3
                    color: Qt.alpha(root.theme.muted, 0.6)
                }
                MouseArea {
                    anchors { top: parent.top; bottom: parent.bottom }
                    anchors.horizontalCenter: parent.horizontalCenter
                    width: 14
                    cursorShape: Qt.SizeHorCursor
                    property real grabDelta: 0
                    onPressed: (mouse) => {
                        var p = mapToItem(mainArea, mouse.x, mouse.y);
                        grabDelta = (root.splitEff + 12) - p.x;
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return;
                        var p = mapToItem(mainArea, mouse.x, mouse.y);
                        root.splitW = Math.max(0, Math.min(p.x + grabDelta - 12, root.splitMax));
                    }
                    onReleased: root.saveSplit()
                }
            }
        }

        // 底部：配色预览
        Item {
            id: paletteBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 16; anchors.rightMargin: 16
            height: 56
            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 1; color: Qt.alpha(root.theme.muted, 0.25)
            }
            Text {
                anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                text: "hellwal 取色预览"
                font.family: root.theme.fontFamily; font.pixelSize: 12; font.bold: true; color: root.theme.fg
            }
            Row {
                id: swatchRow
                anchors { left: parent.left; leftMargin: 110; verticalCenter: parent.verticalCenter }
                spacing: 12
                Repeater {
                    model: [
                        { label: "BG", hex: root.palHex("bg") },
                        { label: "FG", hex: root.palHex("fg") },
                        { label: "ACCENT", hex: root.palHex("accent") },
                        { label: "MUTED", hex: root.palHex("muted") }
                    ]
                    delegate: Item {
                        required property var modelData
                        width: 64; height: 32
                        Rectangle {
                            anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                            width: 28; height: 28; radius: 6
                            color: modelData.hex
                            border.color: Qt.alpha(root.theme.fg, 0.3); border.width: 1
                        }
                        Text {
                            anchors { left: parent.left; leftMargin: 32; verticalCenter: parent.verticalCenter }
                            text: modelData.label
                            font.family: root.theme.fontFamily; font.pixelSize: 10; color: root.theme.muted
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.copyColor(modelData.hex, modelData.label)
                        }
                    }
                }
            }
            Text {
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "回车应用 · Esc 关闭"
                font.family: root.theme.fontFamily; font.pixelSize: 11; color: root.theme.muted
            }
        }
    }
}
