import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// 壁纸选择器：左大预览 + 可拖竖线 + 右缩略图网格（1~3 列随宽） + 下配色预览。
// 竖线可拖：往左拖网格变宽、列数变多，拖到 0 预览消失变纯网格；位置持久化到 ~/.cache/by-mgr/qs-picker-split。
// PgUp/PgDn 在 4 档间跳（大预览宽 0/320/480/630），←/→ 单步选图，↑/↓ 跳一行；拖竖线全程无极、松手存精确值；档位只走 PgUp/PgDn。
// 外壳 900×600 居中，背景 Theme.bg（跟随配色，不全屏、不透明窗、不写死深棕）。
// 顶栏只留标题 + ✕。无过渡面板、无收藏/随机/应用主按钮、无上一下张、无徽标/说明。
// 过渡用原来默认 awww --transition-type random，UI 不选。
// 动效（2026-10-22 按 mock 定稿参数）：窗口落下式入场——壳 opacity 0→1、y -28→0、
// scale 0.97→1，400ms OutCubic；内容分层跟进（预览延迟 40ms、scale 1.02→1、360ms；
// 缩略图每张延迟 60+i×20ms 封顶 120ms、y -10→0、200ms；配色条延迟 160ms、y -8→0、200ms；子元素与壳同向下落）。
// 壳的动画只绑开关状态，不等图片解码。切图时预览只做 180ms 交叉淡化（WallpaperPreview），
// 无位移无缩放。退出比入场快：Esc 170ms 原路收回（InCubic）；应用 180ms 淡出+下沉 10px，
// 让位给桌面壁纸的 awww 2s 过渡。presented 状态机保证退出播完才真正隐藏窗口。
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

    // 开关动效状态机：presented=true 期间窗口才可见（shell.qml 的 visible 绑它）；
    // 关闭先播退出动画、播完才置 false 真正隐藏，保证退出不被 visible 瞬间切断。
    // closeMode: "esc" 取消类关闭（Esc/✕/点背景）原路收回；"apply" 应用关闭淡出下沉。
    property bool presented: false
    property bool closing: false
    property string closeMode: "esc"
    // 入场窗口期标记：只有此期间新建的缩略图 delegate 才播错峰入场，滚动新建的不播
    property bool entering: false

    function beginClose() {
        if (root.closing || !root.presented) return;
        root.closing = true;
        root.entering = false;
        enterAnim.stop();
        if (root.closeMode === "apply") applyExitAnim.restart();
        else escExitAnim.restart();
    }
    function finishClose() {
        root.presented = false;
        root.closing = false;
        root.closeMode = "esc";
    }
    // 每个壁纸的信息：name -> {w, h, size}，由 infoProc 批量 file+stat 填充，失败则只显示名字
    property var infoMap: ({})

    // 可拖竖线：左侧预览区宽度（-1 = 未初始化用默认）；splitEff 为钳制后的生效值
    property real splitW: -1
    readonly property real splitMax: Math.max(0, mainArea.width - 232)
    readonly property real splitEff: root.splitW < 0 ? Math.max(0, mainArea.width - 240) : Math.max(0, Math.min(root.splitW, root.splitMax))

    // 布局档位：大预览宽（第 4 档 630 ≈ 当前默认 628），只走 PgUp/PgDn；拖竖线全程无极、松手存精确值
    readonly property var gears: [0, 320, 480, 630]

    // 配色预览（跟随选中壁纸，不读 global-palette.env）：空 = 未算出，UI 回落 Theme 色
    property var previewPalette: ({})
    property var paletteCache: ({})
    property string paletteWantKey: ""
    property string paletteWantOrig: ""
    property string paletteBusyKey: ""

    function shQuote(s) {
        return "'" + String(s || "").replace(/'/g, "'\"'\"'") + "'";
    }
    function saveSplit() {
        Exec.sh("printf '%s' " + Math.round(root.splitEff) + " > ~/.cache/by-mgr/qs-picker-split");
    }
    function saveSplitValue(v) {
        Exec.sh("printf '%s' " + Math.round(v) + " > ~/.cache/by-mgr/qs-picker-split");
    }
    // PgUp/PgDn 切档位：不在档上时去相邻的下一档（PgDn 往高、PgUp 往低），在档上时去相邻档；到头不动；
    // 滑动只走 gearAnim（不用 Behavior，拖动也要经 splitW）
    function stepGear(d) {
        if (root.splitW < 0) root.splitW = root.splitEff;
        var w = Math.round(root.splitEff);
        var target = -1;
        if (d > 0) {
            for (var i = 0; i < root.gears.length; i++)
                if (root.gears[i] > w) { target = root.gears[i]; break; }
        } else {
            for (var j = root.gears.length - 1; j >= 0; j--)
                if (root.gears[j] < w) { target = root.gears[j]; break; }
        }
        if (target < 0 || target === Math.round(root.splitW)) return;
        gearAnim.to = target;
        gearAnim.restart();
        root.saveSplitValue(target);
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
    // 双击直接应用：绕过 trySelect 的节流与同图守卫，选中即应用
    function selectAndApply(idx) {
        var n = root.wallFiles.length;
        if (n <= 0 || idx < 0 || idx >= n) return;
        root.lastSwitchMs = Date.now();
        root.selectedIndex = idx;
        root.requestPalette(root.selectedItem());
        root.applySelected();
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
        // 原来默认：awww random + theme-sync --no-render（仅同步配色，不双渲染）；-a 同时发给 backdrop 实例，保证 Overview 壁纸跟随
        Exec.sh("awww img -a " + q + " --transition-type random --transition-pos center --transition-duration 2; bash ~/.config/niri/scripts/theme-sync.sh --no-render " + q + "; notify-send \"壁纸已更换\" " + root.shQuote(root.wallBase(it.url)) + " -i " + q);
        root.current = p;
        root.closeMode = "apply";
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
    // 选中哪张就算哪张的最终四色：调 theme-sync.sh --preview <原图>，与实际应用
    // 同一段取色 + 昼夜后处理 + 对比度守卫，干跑只输出 JSON，不写盘、不动主题。
    function requestPalette(item) {
        if (!item) return;
        var key = root.paletteKeyFor(item);
        if (key === "") return;
        var hit = root.paletteCache[key];
        if (hit) { root.previewPalette = hit; return; }
        root.paletteWantKey = key;
        root.paletteWantOrig = root.filePath(String(item.url || ""));
        if (!paletteProc.running) root.startPalette();
    }
    function startPalette() {
        root.paletteBusyKey = root.paletteWantKey;
        var orig = root.paletteWantOrig;
        // 传原图：theme-sync 自己做工作小图与 webp/avif 回退，预览与实际输入图统一
        var script = "bash ~/.config/niri/scripts/theme-sync.sh --preview " + root.shQuote(orig) + " 2>/dev/null";
        paletteProc.command = ["bash", "-c", script];
        paletteProc.running = true;
    }
    function applyPaletteJson(text, key) {
        if (!text || key === "") return;
        try {
            var j = JSON.parse(text);
            // theme-sync.sh --preview 的扁平输出：最终四色（已含昼夜后处理+对比度守卫）
            if (j.bg && j.fg && j.accent && j.muted) {
                var res = { bg: String(j.bg), fg: String(j.fg), accent: String(j.accent), muted: String(j.muted) };
                var m = Object.assign({}, root.paletteCache);
                m[key] = res;
                root.paletteCache = m;
                // 只接受当前选中的结果，旧请求后到不覆盖新选中
                if (key === root.paletteKeyFor(root.selectedItem()))
                    root.previewPalette = res;
                return;
            }
            var sp = j.special || {};
            var co = j.colors || {};
            var bg = String(sp.background || co.color0 || "#1e1e2e");
            var fg = String(sp.foreground || co.color15 || "#ffffff");
            var ac = String(co.color4 || "#89b4fa");
            var mu = String(co.color8 || co.color0 || "#45475a");
            if (bg === "#000000" || bg === "#111111") bg = "#1e1e2e";
            if (mu === "#000000" || mu === "#111111") mu = "#2a2b3c";
            var res2 = { bg: bg, fg: fg, accent: ac, muted: mu };
            var m2 = Object.assign({}, root.paletteCache);
            m2[key] = res2;
            root.paletteCache = m2;
            // 只接受当前选中的结果，旧请求后到不覆盖新选中
            if (key === root.paletteKeyFor(root.selectedItem()))
                root.previewPalette = res2;
        } catch (e) {}
    }
    function copyColor(hex, label) {
        var q = root.shQuote(String(hex || ""));
        Exec.sh("printf '%s' " + q + " | wl-copy; notify-send \"已复制色值\" " + root.shQuote(label + " " + hex));
    }
    onPickerOpenChanged: {
        if (root.pickerOpen) {
            // 打开：停掉可能在播的退出动画，复位到入场起帧再播入场（壳不等图片解码）
            escExitAnim.stop();
            applyExitAnim.stop();
            root.closing = false;
            root.closeMode = "esc";
            root.presented = true;
            shellCard.opacity = 0;
            shellShift.y = -28;
            shellScaleT.xScale = 0.97;
            shellScaleT.yScale = 0.97;
            flipWrap.opacity = 0;
            flipScaleT.xScale = 1.02;
            flipScaleT.yScale = 1.02;
            paletteBar.opacity = 0;
            paletteShift.y = -8;
            root.entering = true;
            enterGate.restart();
            enterAnim.restart();
            root.refreshAll();
            root.forceActiveFocus();
        } else if (root.presented) {
            // 关闭（含快捷键切换关）：播退出动画，播完 finishClose 才隐藏
            root.beginClose();
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

    // 选中壁纸的取色预览：theme-sync.sh --preview 干跑同一套算法（只输出最终四色 JSON，不应用、不写 global-palette.env）
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
        } else if (event.key === Qt.Key_PageUp) {
            root.stepGear(-1); event.accepted = true;
        } else if (event.key === Qt.Key_PageDown) {
            root.stepGear(1); event.accepted = true;
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

    // 外壳：Theme.bg，radius 16。入场/退出动效作用在这一层（位移+缩放+透明）
    ClippingRectangle {
        id: shellCard
        anchors.fill: parent
        radius: 16
        transform: [
            Translate { id: shellShift; y: 0 },
            Scale {
                id: shellScaleT
                origin.x: shellCard.width / 2
                origin.y: shellCard.height / 2
                xScale: 1; yScale: 1
            }
        ]
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

                // 大预览：UI 与动效隔离（WallpaperPreview 组件，切图只交叉淡化）；
                // 入场时这一层延迟 40ms 以 scale 1.02→1 + 淡入放稳
                Item {
                    id: flipWrap
                    anchors { top: parent.top; left: parent.left; right: parent.right }
                    height: root.splitEff >= 200 ? parent.height - 52 : parent.height
                    clip: true
                    transform: Scale {
                        id: flipScaleT
                        origin.x: flipWrap.width / 2
                        origin.y: flipWrap.height / 2
                        xScale: 1; yScale: 1
                    }

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
                    // 大预览双击 = 应用当前选中
                    MouseArea {
                        anchors.fill: parent
                        onDoubleClicked: root.applySelected()
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
                        id: dlg
                        required property var modelData
                        required property int index
                        width: grid.cellWidth
                        height: grid.cellHeight
                        transform: Translate { id: dlgShift; y: 0 }
                        // 入场错峰：仅打开窗口期新建的 delegate 播（延迟 60+i×20、封顶 120ms，
                        // 保证末张约 320ms 完成）；滚动新建的直接静止显示
                        Component.onCompleted: {
                            if (root.entering) {
                                dlg.opacity = 0;
                                dlgShift.y = -10;
                                dlgDelay.interval = 60 + Math.min(index, 3) * 20;
                                dlgDelay.restart();
                            }
                        }
                        Timer {
                            id: dlgDelay
                            repeat: false
                            onTriggered: dlgEnter.restart()
                        }
                        ParallelAnimation {
                            id: dlgEnter
                            NumberAnimation { target: dlg; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                            NumberAnimation { target: dlgShift; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
                        }
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
                            onDoubleClicked: root.selectAndApply(index)
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
                        gearAnim.stop();
                        var p = mapToItem(mainArea, mouse.x, mouse.y);
                        grabDelta = (root.splitEff + 12) - p.x;
                    }
                    onPositionChanged: (mouse) => {
                        if (!pressed) return;
                        var p = mapToItem(mainArea, mouse.x, mouse.y);
                        root.splitW = Math.max(0, Math.min(p.x + grabDelta - 12, root.splitMax));
                    }
                    // 松手存精确值（无极，不吸附到档位）
                    onReleased: root.saveSplit()
                }
            }
        }

        // 底部：配色预览（入场延迟 160ms 从上方 8px 落下淡入，与壳同向）
        Item {
            id: paletteBar
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
            anchors.leftMargin: 16; anchors.rightMargin: 16
            height: 56
            transform: Translate { id: paletteShift; y: 0 }
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
                id: hintText
                anchors { right: parent.right; verticalCenter: parent.verticalCenter }
                text: "PgUp/PgDn 档位 · ← → 选图 · 回车应用 · Esc 关闭"
                font.family: root.theme.fontFamily; font.pixelSize: 11; color: root.theme.muted
            }
        }
    }

    // 档位滑动：200ms OutCubic，只动 splitW；拖动按住时先停它（见 divider onPressed）
    NumberAnimation {
        id: gearAnim
        target: root; property: "splitW"
        duration: 200; easing.type: Easing.OutCubic
    }

    // ===== 开关动效（参数按 2026-10-22 mock 定稿）=====
    // 入场：壳 400ms OutCubic（opacity 0→1、y -28→0、scale 0.97→1）；
    // 预览延迟 40ms、360ms（opacity 0→1、scale 1.02→1）；配色条延迟 160ms、200ms（opacity 0→1、y -8→0）
    ParallelAnimation {
        id: enterAnim
        ParallelAnimation {
            NumberAnimation { target: shellCard; property: "opacity"; to: 1; duration: 400; easing.type: Easing.OutCubic }
            NumberAnimation { target: shellShift; property: "y"; to: 0; duration: 400; easing.type: Easing.OutCubic }
            NumberAnimation { target: shellScaleT; property: "xScale"; to: 1; duration: 400; easing.type: Easing.OutCubic }
            NumberAnimation { target: shellScaleT; property: "yScale"; to: 1; duration: 400; easing.type: Easing.OutCubic }
        }
        SequentialAnimation {
            PauseAnimation { duration: 40 }
            ParallelAnimation {
                NumberAnimation { target: flipWrap; property: "opacity"; to: 1; duration: 360; easing.type: Easing.OutCubic }
                NumberAnimation { target: flipScaleT; property: "xScale"; to: 1; duration: 360; easing.type: Easing.OutCubic }
                NumberAnimation { target: flipScaleT; property: "yScale"; to: 1; duration: 360; easing.type: Easing.OutCubic }
            }
        }
        SequentialAnimation {
            PauseAnimation { duration: 160 }
            ParallelAnimation {
                NumberAnimation { target: paletteBar; property: "opacity"; to: 1; duration: 200; easing.type: Easing.OutCubic }
                NumberAnimation { target: paletteShift; property: "y"; to: 0; duration: 200; easing.type: Easing.OutCubic }
            }
        }
    }

    // 入场窗口期：700ms 后关闭 entering，之后滚动新建的缩略图不再播错峰
    Timer {
        id: enterGate
        interval: 700
        repeat: false
        onTriggered: root.entering = false
    }

    // 退出（Esc 类）：170ms InCubic 原路收回（opacity→0、y→-28、scale→0.97）
    ParallelAnimation {
        id: escExitAnim
        NumberAnimation { target: shellCard; property: "opacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: shellShift; property: "y"; to: -28; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: shellScaleT; property: "xScale"; to: 0.97; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: shellScaleT; property: "yScale"; to: 0.97; duration: 170; easing.type: Easing.InCubic }
        onFinished: root.finishClose()
    }

    // 退出（应用）：180ms 淡出 + 下沉 10px，让位桌面壁纸过渡
    ParallelAnimation {
        id: applyExitAnim
        NumberAnimation { target: shellCard; property: "opacity"; to: 0; duration: 180; easing.type: Easing.InCubic }
        NumberAnimation { target: shellShift; property: "y"; to: 10; duration: 180; easing.type: Easing.InCubic }
        onFinished: root.finishClose()
    }
}
