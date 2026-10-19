import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// 设置边栏 C 精修版（新增，不删原弹窗）：
// 右侧临时滑出，窄态 460（分区滚动），壁纸态 760（左大预览 + 右网格）。
// 颜色只用 Theme 绑定，不写死。原弹窗（ControlCenter/WallpaperCard 等）全部保留。
Item {
    id: root
    property var theme
    signal requestClose

    property bool isWallpaper: UiState.sidebarWallpaper
    property var wallFiles: []
    // 卡顿修1：批量更新——SplitParser 先攒 wallFilesBuf，进程结束一次赋值（31 次重置 → 1 次）
    property var wallFilesBuf: []
    property var recentWalls: []
    property string currentWall: ""
    property int previewIndex: -1
    property real imgOpacity: 1
    property string songTitle: ""
    property string songArtist: ""
    property string songCover: ""
    property string cardTab: "wallpaper"
    property bool musicExpanded: false
    // 先修3：滚动位置暂存（窄态 / 壁纸网格各存一份，进出不重置）
    property real savedNarrowY: 0
    // 当前壁纸的 hellwal 四色（只取 JSON 预览，不应用）
    property color wallBg: root.theme.bg
    property color wallFg: root.theme.fg
    property color wallAccent: root.theme.accent
    property color wallMuted: root.theme.muted
    function refreshWallPalette() {
        var u = root.previewUrl();
        if (!u) return;
        var p = String(u).replace(/^file:\/\//, "").replace(/'/g, "'\\''");
        wallPaletteProc.command = ["bash", "-c", "hellwal --no-cache --skip-term-colors -i '" + p + "' -j 2>/dev/null"];
        wallPaletteProc.running = true;
    }
    Process {
        id: wallPaletteProc
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text);
                    var sp = j.special || {};
                    var co = j.colors || {};
                    var bg = String(sp.background || co.color0 || "#1e1e2e");
                    var fg = String(sp.foreground || co.color15 || "#ffffff");
                    var ac = String(co.color4 || "#89b4fa");
                    var mu = String(co.color8 || co.color0 || "#45475a");
                    if (bg === "#000000" || bg === "#111111") bg = "#1e1e2e";
                    if (mu === "#000000" || mu === "#111111") mu = "#2a2b3c";
                    root.wallBg = bg; root.wallFg = fg; root.wallAccent = ac; root.wallMuted = mu;
                } catch (e) {}
            }
        }
    }
    property real savedWallY: 0
    // 先修2：壁纸态入场淡入（左预览/过渡/按钮 200ms，网格延迟 60ms 后 200ms）
    property real previewOpacity: 0
    property real gridOpacity: 0
    function enterWallpaper() {
        root.savedNarrowY = narrowScroll.contentY;
        UiState.sidebarWallpaper = true;
        root.previewOpacity = 0;
        root.gridOpacity = 0;
        previewFadeAnim.start();
        gridFadeSeq.start();
        restoreWallTimer.restart();
    }
    function exitWallpaper() {
        root.savedWallY = wallGrid.contentY;
        UiState.sidebarWallpaper = false;
        restoreNarrowTimer.restart();
    }


    function wallBase(url) {
        var s = String(url || "");
        var i = s.lastIndexOf("/");
        return i >= 0 ? s.slice(i + 1) : s;
    }
    function isCurrent(url) {
        var u = String(url || "");
        return ("file://" + root.currentWall === u) || (root.currentWall === u.replace(/^file:\/\//, ""));
    }
    function previewItem() {
        if (root.previewIndex >= 0 && root.previewIndex < root.wallFiles.length)
            return root.wallFiles[root.previewIndex];
        for (var i = 0; i < root.wallFiles.length; i++) {
            if (root.isCurrent(root.wallFiles[i].url))
                return root.wallFiles[i];
        }
        return root.wallFiles.length > 0 ? root.wallFiles[0] : null;
    }
    function previewThumb() {
        var it = root.previewItem();
        return it ? (it.thumb || it.url || "") : "";
    }
    function previewUrl() {
        var it = root.previewItem();
        return it ? (it.url || "") : "";
    }
    function previewName() {
        var it = root.previewItem();
        return it ? root.wallBase(it.url) : "暂无壁纸";
    }
    function applyPreview() {
        var u = root.previewUrl();
        if (u !== "")
            root.applyWall(u);
    }
    function applyWall(fileUrl) {
        var p = String(fileUrl).replace(/^file:\/\//, "");
        Exec.sh('bash ~/.config/niri/scripts/theme-sync.sh "' + p + '"');
        refreshTimer.restart();
    }
    function styleName(id) {
        if (id === "fade") return "淡入";
        if (id === "off") return "关闭";
        if (id === "random") return "随机";
        if (id === "wipe") return "横扫";
        if (id === "outside") return "反波";
        if (id === "twinkle") return "闪烁";
        return "追逐波";
    }
    function styleValid(id) {
        return id === "wave" || id === "fade" || id === "off" || id === "random" || id === "wipe" || id === "outside" || id === "twinkle";
    }
    function refreshAll() {
        root.wallFilesBuf = [];
        lsProc.running = true;
        curProc.running = true;
        transProc.running = true;
    }
    function patName(i) {
        return ["自动", "起伏", "斜纹", "呼吸", "交错", "脉冲", "驼峰", "闪烁", "峭壁", "混合"][i];
    }
    function fmtTime(d) {
        var t = d instanceof Date ? d : new Date(d);
        return String(t.getHours()).padStart(2, "0") + ":" + String(t.getMinutes()).padStart(2, "0");
    }
    onVisibleChanged: { if (visible) { root.refreshAll(); root.refreshWallPalette(); } }
    Component.onCompleted: root.refreshAll()
    onPreviewIndexChanged: {
        root.imgOpacity = 0;
        fadeTimer.restart();
    }
    Timer {
        id: fadeTimer
        interval: 30
        onTriggered: root.imgOpacity = 1
    }
    // 先修2：入场淡入动画（显式 Animation，避免 Behavior 在重置时二次动画）
    NumberAnimation {
        id: previewFadeAnim
        target: root
        property: "previewOpacity"
        from: 0; to: 1; duration: 200
        easing.type: Easing.OutCubic
    }
    SequentialAnimation {
        id: gridFadeSeq
        PauseAnimation { duration: 60 }
        NumberAnimation {
            target: root
            property: "gridOpacity"
            from: 0; to: 1; duration: 200
            easing.type: Easing.OutCubic
        }
    }
    // 先修3：恢复滚动位置（延迟一帧，等布局 contentHeight 就绪再恢复）
    Timer {
        id: restoreNarrowTimer
        interval: 30
        onTriggered: {
            var maxY = Math.max(0, narrowScroll.contentHeight - narrowScroll.height);
            narrowScroll.contentY = Math.min(root.savedNarrowY, maxY);
        }
    }
    Timer {
        id: restoreWallTimer
        interval: 30
        onTriggered: {
            var maxY = Math.max(0, wallGrid.contentHeight - wallGrid.height);
            wallGrid.contentY = Math.min(root.savedWallY, maxY);
        }
    }
    Timer {
        id: songTimer
        interval: 2000
        repeat: true
        running: true
        triggeredOnStart: true
        onTriggered: {
            try {
                var p = MprisSelect.pick();
                root.songTitle = p ? (p.trackTitle || "") : "";
                root.songArtist = p ? (p.trackArtist || "") : "";
                root.songCover = p ? (p.trackArtUrl || "") : "";
            } catch (e) { root.songTitle = ""; root.songArtist = ""; root.songCover = ""; }
        }
    }
    Timer {
        id: refreshTimer
        interval: 1500
        onTriggered: { curProc.running = true; }
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
                        root.wallFilesBuf.push({ name: j.name, url: j.url, thumb: j.thumb || j.url });
                } catch (e) {}
            }
        }
        // 卡顿修1：进程结束时一次赋值，避免逐行 concat 造成 31 次 GridView 全量重置
        onRunningChanged: {
            if (!lsProc.running) {
                root.wallFiles = root.wallFilesBuf;
                root.recentWalls = root.wallFilesBuf.slice(0, 4);
            }
        }
    }
    Process {
        id: curProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/last-wallpaper 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { root.currentWall = this.text.trim(); }
        }
    }
    Process {
        id: transProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/qs-transition 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (root.styleValid(t))
                    UiState.transitionStyle = t;
            }
        }
    }

    // 音量后端（ControlCenter 同款 wpctl 轮询）
    Item {
        id: volSink
        property real vol: 0
        property bool muted: false
        function refresh() { volPoller.running = true; }
        function setVol(ratio, commit) {
            var v = Math.max(0, Math.min(1, ratio)).toFixed(2);
            if (commit)
                Exec.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v]);
            else
                Exec.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null; wpctl set-volume @DEFAULT_AUDIO_SINK@ " + v]);
            volSink.refresh();
        }
        Component.onCompleted: volSink.refresh()
        Timer {
            interval: 2000; repeat: true; running: true
            onTriggered: { if (!volPoller.running) volPoller.running = true; }
        }
        Process {
            id: volPoller
            command: ["bash", "-c", Exec.commonDir + "/audio.sh"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var j = JSON.parse(this.text);
                        volSink.vol = Math.max(0, Math.min(1, Number(j.vol || 0)));
                        volSink.muted = !!j.muted;
                    } catch (e) {}
                }
            }
        }
    }

    // 风格切换状态（ControlCenter 同款：detect + qs-switch）
    Item {
        id: styleState
        property string current: ""
        property string styleDir: Quickshell.shellDir + "/styles"
        function detect() { detectProc.running = true; }
        function launch(id) {
            // 先修4：切风格先关边栏（再执行切换），避免重启后残留空壳
            UiState.sidebarOpen = false;
            UiState.sidebarWallpaper = false;
            if (id === "waybar") {
                Exec.sh("pkill -x quickshell; pkill waybar 2>/dev/null; pkill cava 2>/dev/null; waybar & disown");
            } else {
                Exec.sh("bash " + styleState.styleDir + "/qs-switch.sh " + id);
            }
        }
        Component.onCompleted: styleState.detect()
        Process {
            id: detectProc
            command: ["bash", "-c", "pgrep -x waybar >/dev/null && echo WAYBAR || pgrep -af '^quickshell -p' | head -n 1"]
            stdout: StdioCollector {
                onStreamFinished: {
                    var t = String(text).trim();
                    if (t === "WAYBAR") { styleState.current = "waybar"; return; }
                    var m = /-p (\S+)/.exec(t);
                    if (m) {
                        var d = m[1];
                        if (d === Quickshell.shellDir) styleState.current = "default";
                        else styleState.current = d.split("/").pop();
                    }
                }
            }
        }
    }

    // 外壳：圆角 16，Theme 绑定，不写死颜色
    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
        clip: true

        Column {
            anchors { fill: parent; margins: 16 }
            spacing: 12

            // 标题行
            Item {
                width: parent.width
                height: 28
                Row {
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                    spacing: 8
                    Text {
                        visible: root.isWallpaper
                        text: "←"
                        font.family: root.theme.fontFamily; font.pixelSize: 16; font.bold: true
                        color: root.theme.fg
                        MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: root.exitWallpaper() }
                    }
                    Text {
                        text: root.isWallpaper ? "壁纸" : "Settings"
                        font.family: root.theme.fontFamily; font.pixelSize: 16; font.bold: true
                        color: root.theme.fg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: "✕"
                    font.pixelSize: 13
                    color: root.theme.muted
                    MouseArea { anchors.fill: parent; anchors.margins: -8; onClicked: root.requestClose() }
                }
            }

            // ============ 窄态：分区滚动 ============
            Flickable {
                id: narrowScroll
                visible: !root.isWallpaper
                width: parent.width
                height: parent.height - 28 - 12
                clip: true
                contentWidth: width
                contentHeight: narrowCol.implicitHeight
                Column {
                    id: narrowCol
                    width: parent.width
                    spacing: 12

                    // ---- 快捷 ----
                    Row {
                        spacing: 6
                        Text { text: Icons.sliders; font.family: root.theme.fontFamily; font.pixelSize: 14; color: root.theme.fg }
                        Text { text: "快捷"; font.family: root.theme.fontFamily; font.pixelSize: 14; font.bold: true; color: root.theme.fg }
                    }
                    // 快捷开关：Wi-Fi / 蓝牙 / 勿扰 / 护眼
                    QuickToggles {
                        width: parent.width
                        theme: root.theme
                        exec: Exec
                    }
                    Rectangle {
                        width: parent.width; height: 56; radius: 12
                        color: Qt.alpha(root.theme.accent, 0.18)
                        Row {
                            anchors { fill: parent; margins: 12 }
                            spacing: 10
                            // 图标固定 24 宽容器，字形随音量变化时布局不抖
                            Item {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 24; height: 24
                                Text {
                                    anchors.centerIn: parent
                                    text: volSink.muted ? "󰝟" : (volSink.vol <= 0 ? "" : volSink.vol < 0.6 ? "" : "")
                                    font.pixelSize: 17; font.family: root.theme.fontFamily; color: root.theme.fg
                                }
                                MouseArea {
                                    anchors.fill: parent; anchors.margins: -6
                                    onClicked: { Exec.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]); volSink.refresh(); }
                                }
                            }
                            SegmentBar {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24 - 44 - 20 - 20
                                theme: root.theme; value01: volSink.vol
                                onMoved: ratio => volSink.setVol(ratio, false)
                                onReleased: ratio => volSink.setVol(ratio, true)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter; width: 44
                                text: volSink.muted ? "静音" : Math.round(volSink.vol * 100) + "%"
                                font.pixelSize: 12; font.family: root.theme.fontFamily; color: root.theme.fg
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    // 亮度：默认只显示内接，点击图标展开外接
                    // 亮度：只渲染当前屏对应的（eDP=内接，其他=外接），无需展开/图标区分
                    BrightnessRow {
                        theme: root.theme
                        mode: (UiState.sidebarScreen.indexOf("eDP") >= 0 || UiState.sidebarScreen === "") ? "internal" : "external"
                    }


                    // ---- 风格 ----
                    Row {
                        spacing: 6
                        Text { text: "\uF1FC"; font.family: root.theme.fontFamily; font.pixelSize: 14; color: root.theme.fg }
                        Text { text: "风格"; font.family: root.theme.fontFamily; font.pixelSize: 14; font.bold: true; color: root.theme.fg }
                    }
                    Row {
                        width: parent.width; spacing: 8
                        Repeater {
                            model: ["waybar", "default", "duo"]
                            Rectangle {
                                required property string modelData
                                width: (parent.width - 16) / 3; height: 64; radius: 12
                                color: styleState.current === modelData ? Qt.alpha(root.theme.accent, 0.35) : "transparent"
                                border.width: 1
                                border.color: styleState.current === modelData ? root.theme.accent : root.theme.muted
                                Column {
                                    anchors { fill: parent; margins: 8 }
                                    spacing: 4
                                    Rectangle {
                                        width: parent.width; height: 14; radius: 4
                                        color: modelData === "duo" ? "transparent" : Qt.alpha(root.theme.fg, 0.25)
                                        border.width: modelData === "duo" ? 1 : 0
                                        border.color: root.theme.muted
                                        Row {
                                            anchors.centerIn: parent; spacing: 3
                                            visible: modelData === "duo"
                                            Rectangle { width: 16; height: 6; radius: 3; color: Qt.alpha(root.theme.fg, 0.5) }
                                            Rectangle { width: 6; height: 6; radius: 3; color: Qt.alpha(root.theme.fg, 0.5) }
                                            Rectangle { width: 16; height: 6; radius: 3; color: Qt.alpha(root.theme.fg, 0.5) }
                                        }
                                    }
                                    Rectangle {
                                        width: parent.width; height: 8; radius: 4
                                        color: modelData === "default" ? Qt.alpha(root.theme.fg, 0.25) : "transparent"
                                        visible: modelData === "default"
                                    }
                                    Text {
                                        text: modelData + (styleState.current === modelData ? " · 当前" : "")
                                        font.family: root.theme.fontFamily; font.pixelSize: 12
                                        color: root.theme.fg
                                    }
                                }
                                MouseArea { anchors.fill: parent; onClicked: styleState.launch(parent.modelData) }
                            }
                        }
                    }
                    Rectangle {
                        width: parent.width; height: 44; radius: 12
                        color: Qt.alpha(root.theme.accent, 0.25)
                        Row {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            spacing: 8
                            Text { text: "昼夜"; font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true; color: root.theme.fg; anchors.verticalCenter: parent.verticalCenter }
                            Text { text: BarState.themeT !== "" ? BarState.themeT : "…"; font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.muted; anchors.verticalCenter: parent.verticalCenter }
                            Item { width: 1; height: 1 }
                            Text { text: "切换"; font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.accent; anchors.verticalCenter: parent.verticalCenter }
                        }
                        MouseArea { anchors.fill: parent; onClicked: Exec.sh("bash " + Quickshell.env("HOME") + "/.config/niri/scripts/toggle-theme.sh"); }
                    }

                    // ---- 壁纸 / 音乐切换 ----
                    Rectangle {
                        width: parent.width; height: 36; radius: 10
                        color: Qt.alpha(root.theme.muted, 0.25)
                        Rectangle {
                            width: parent.width / 2 - 3; height: 30; radius: 8
                            x: root.cardTab === "wallpaper" ? 3 : parent.width / 2
                            y: 3
                            color: root.theme.accent
                            Behavior on x { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                        Row {
                            anchors.fill: parent
                            Rectangle {
                                width: parent.width / 2; height: parent.height; color: "transparent"
                                Text {
                                    anchors.centerIn: parent; text: "壁纸"
                                    font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                    color: root.cardTab === "wallpaper" ? root.theme.bg : root.theme.fg
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.cardTab = "wallpaper" }
                            }
                            Rectangle {
                                width: parent.width / 2; height: parent.height; color: "transparent"
                                Text {
                                    anchors.centerIn: parent; text: "音乐"
                                    font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                    color: root.cardTab === "music" ? root.theme.bg : root.theme.fg
                                }
                                MouseArea { anchors.fill: parent; onClicked: root.cardTab = "music" }
                            }
                        }
                    }
                    SidebarWallpaperCard {
                        width: parent.width
                        visible: root.cardTab === "wallpaper"
                        theme: root.theme
                        wallUrl: root.previewUrl()
                        wallName: root.previewName()
                        wallBg: root.wallBg
                        wallFg: root.wallFg
                        wallAccent: root.wallAccent
                        wallMuted: root.wallMuted
                        onClicked: {
                            var s = UiState.sidebarScreen;
                            if (s === "" && Quickshell.screens.length > 0)
                                s = Quickshell.screens[0].name;
                            UiState.toggleWallpaperPicker(s);
                        }
                    }
                    SidebarMusicCard {
                        width: parent.width
                        visible: root.cardTab === "music"
                        theme: root.theme
                        songTitle: root.songTitle
                        songArtist: root.songArtist
                        songCover: root.songCover
                    }
                    // ---- 通知 ----
                    Row {
                        spacing: 6
                        Text { text: Icons.bell; font.family: root.theme.fontFamily; font.pixelSize: 14; color: root.theme.fg }
                        Text { text: "通知"; font.family: root.theme.fontFamily; font.pixelSize: 14; font.bold: true; color: root.theme.fg }
                        Item { width: 1; height: 1 }
                        Text { text: Notifs.history.length + " 条"; font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.muted }
                        Text {
                            text: "清空"; font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.fg
                            MouseArea { anchors.fill: parent; anchors.margins: -6; onClicked: Notifs.clearHistory() }
                        }
                    }
                    Text {
                        visible: Notifs.history.length === 0
                        width: parent.width; text: "暂无通知"
                        font.family: root.theme.fontFamily; font.pixelSize: 13; color: root.theme.muted
                        horizontalAlignment: Text.AlignHCenter
                    }
                    Repeater {
                        model: Notifs.history.slice(0, 3)
                        Rectangle {
                            required property var modelData
                            width: narrowCol.width; height: notifCol.implicitHeight + 16; radius: 12
                            color: Qt.alpha(root.theme.accent, 0.25)
                            Column {
                                id: notifCol
                                anchors { left: parent.left; right: parent.right; top: parent.top; margins: 8 }
                                spacing: 2
                                Text {
                                    width: parent.width
                                    text: UiState.cleanText(modelData.summary) || "(无标题)"
                                    font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                    color: root.theme.fg; elide: Text.ElideRight
                                }
                                Text {
                                    width: parent.width; visible: UiState.cleanText(modelData.body) !== ""
                                    text: UiState.cleanText(modelData.body)
                                    font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.muted
                                    elide: Text.ElideRight; maximumLineCount: 2
                                }
                            }
                        }
                    }
                    Item { width: 1; height: 4 }
                }
            }

            // ============ 壁纸态：左大预览 + 右网格 ============
            Row {
                visible: root.isWallpaper
                width: parent.width
                height: parent.height - 28 - 12
                spacing: 12

                // 左：大预览 + 过渡预览 + 按钮 + 最近用过
                Column {
                    id: leftCol
                    width: parent.width - 320 - 12
                    height: parent.height
                    spacing: 10

                    Rectangle {
                        width: parent.width; height: Math.min(360, parent.height - 52 - 32 - 80 - 30)
                        radius: 12; color: "transparent"; border.width: 1; border.color: root.theme.muted; clip: true
                        opacity: root.previewOpacity
                        Image {
                            anchors.fill: parent
                            source: root.previewThumb()
                            asynchronous: true; cache: true; smooth: true; mipmap: true
                            fillMode: Image.PreserveAspectCrop
                            opacity: root.imgOpacity
                            Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                        }
                        Rectangle {
                            anchors { left: parent.left; bottom: parent.bottom; margins: 10 }
                            radius: 6; color: Qt.alpha(root.theme.bg, 0.7)
                            width: nameText.implicitWidth + 16; height: 24
                            Text {
                                id: nameText
                                anchors.centerIn: parent
                                text: root.previewName()
                                font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.fg
                            }
                        }
                        Rectangle {
                            anchors { right: parent.right; top: parent.top; margins: 10 }
                            visible: root.isCurrent(root.previewUrl())
                            radius: 6; color: Qt.alpha(root.theme.bg, 0.7)
                            width: curTag.implicitWidth + 12; height: 20
                            Text {
                                id: curTag
                                anchors.centerIn: parent
                                text: "当前"
                                font.family: root.theme.fontFamily; font.pixelSize: 11; color: root.theme.fg
                            }
                        }
                    }
                    // 过渡小动画预览行（7 卡）
                    Row {
                        width: parent.width; spacing: 6
                        opacity: root.previewOpacity
                        Repeater {
                            model: [{ id: "off", name: "关闭" }, { id: "random", name: "随机" }, { id: "wave", name: "追逐波" }, { id: "fade", name: "淡入" }, { id: "wipe", name: "横扫" }, { id: "outside", name: "反波" }, { id: "twinkle", name: "闪烁" }]
                            Rectangle {
                                required property var modelData
                                width: (leftCol.width - 36) / 7; height: 52; radius: 8
                                color: "transparent"
                                border.width: 1
                                border.color: UiState.transitionStyle === modelData.id ? root.theme.accent : root.theme.muted
                                Column {
                                    anchors { fill: parent; margins: 4 }
                                    spacing: 2
                                    Item {
                                        width: parent.width; height: 28; clip: true
                                        Rectangle { anchors.fill: parent; radius: 4; color: Qt.alpha(root.theme.accent, 0.35) }
                                        // 关闭：静态
                                        Rectangle { visible: modelData.id === "off"; anchors.fill: parent; radius: 4; color: Qt.alpha(root.theme.fg, 0.4) }
                                        // 随机：闪烁
                                        Rectangle {
                                            visible: modelData.id === "random"; anchors.fill: parent; radius: 4; color: Qt.alpha(root.theme.fg, 0.5)
                                            opacity: 0.4
                                            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 1; duration: 300 } NumberAnimation { to: 0.4; duration: 300 } }
                                        }
                                        // 追逐波：小条左右扫
                                        Rectangle {
                                            visible: modelData.id === "wave"; width: 10; height: parent.height; radius: 5; color: root.theme.fg
                                            NumberAnimation on x { from: -10; to: parent.width; duration: 900; loops: Animation.Infinite; easing.type: Easing.InOutQuad }
                                        }
                                        // 淡入：呼吸
                                        Rectangle {
                                            visible: modelData.id === "fade"; anchors.fill: parent; radius: 4; color: root.theme.fg
                                            opacity: 0.2
                                            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 0.9; duration: 700 } NumberAnimation { to: 0.2; duration: 700 } }
                                        }
                                        // 横扫：宽度展开
                                        Rectangle {
                                            visible: modelData.id === "wipe"; height: parent.height; radius: 4; color: root.theme.fg
                                            width: 0
                                            SequentialAnimation on width { loops: Animation.Infinite; NumberAnimation { to: parent.width; duration: 700 } PauseAnimation { duration: 200 } NumberAnimation { to: 0; duration: 100 } }
                                        }
                                        // 反波：两边向中间收
                                        Item {
                                            visible: modelData.id === "outside"; anchors.fill: parent
                                            Rectangle {
                                                width: parent.width / 2; height: parent.height; color: root.theme.fg
                                                x: 0
                                                NumberAnimation on x { from: -parent.width / 2; to: 0; duration: 700; loops: Animation.Infinite; easing.type: Easing.InOutQuad }
                                            }
                                            Rectangle {
                                                width: parent.width / 2; height: parent.height; color: root.theme.fg
                                                x: parent.width / 2
                                                NumberAnimation on x { from: parent.width; to: parent.width / 2; duration: 700; loops: Animation.Infinite; easing.type: Easing.InOutQuad }
                                            }
                                        }
                                        // 闪烁：快速闪
                                        Rectangle {
                                            visible: modelData.id === "twinkle"; anchors.fill: parent; radius: 4; color: root.theme.fg
                                            opacity: 0.2
                                            SequentialAnimation on opacity { loops: Animation.Infinite; NumberAnimation { to: 1; duration: 120 } NumberAnimation { to: 0.2; duration: 120 } }
                                        }
                                    }
                                    Text {
                                        anchors.horizontalCenter: parent.horizontalCenter
                                        text: modelData.name
                                        font.family: root.theme.fontFamily; font.pixelSize: 10
                                        color: UiState.transitionStyle === modelData.id ? root.theme.accent : root.theme.muted
                                    }
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: {
                                        UiState.transitionStyle = parent.modelData.id;
                                        Exec.sh("printf '" + parent.modelData.id + "' > ~/.cache/by-mgr/qs-transition");
                                    }
                                }
                            }
                        }
                    }
                    Row {
                        width: parent.width; spacing: 8
                        opacity: root.previewOpacity
                        Rectangle {
                            width: (parent.width - 8) / 2; height: 32; radius: 9
                            color: root.theme.accent
                            Text { anchors.centerIn: parent; text: "应用"; font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true; color: root.theme.bg }
                            MouseArea { anchors.fill: parent; onClicked: root.applyPreview() }
                        }
                        Rectangle {
                            width: (parent.width - 8) / 2; height: 32; radius: 9
                            color: "transparent"; border.width: 1; border.color: root.theme.muted
                            Text { anchors.centerIn: parent; text: "随机一张"; font.family: root.theme.fontFamily; font.pixelSize: 13; color: root.theme.fg }
                            MouseArea { anchors.fill: parent; onClicked: { Exec.sh("bash ~/.config/niri/scripts/wallpaper.sh"); refreshTimer.restart(); } }
                        }
                    }
                    Row {
                        width: parent.width; spacing: 6
                        Text { text: "最近用过"; font.family: root.theme.fontFamily; font.pixelSize: 12; color: root.theme.muted }
                        Repeater {
                            // 卡顿修1：绑专用 recentWalls，去掉内联 .slice(0,4) 造成的 30 次重建
                            model: root.recentWalls
                            ClippingRectangle {
                                required property var modelData
                                width: 40; height: 28; radius: 6
                                Image { anchors.fill: parent; source: modelData.thumb || modelData.url; asynchronous: true; cache: true; fillMode: Image.PreserveAspectFit }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: { for (var i = 0; i < root.wallFiles.length; i++) { if (root.wallFiles[i].url === parent.modelData.url) { root.previewIndex = i; break; } } }
                                }
                            }
                        }
                    }
                }

                // 右：2 列网格
                GridView {
                    id: wallGrid
                    width: 320
                    height: parent.height
                    clip: true
                    opacity: root.gridOpacity
                    cellWidth: Math.floor(width / 2)
                    cellHeight: 132
                    model: root.wallFiles
                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: wallGrid.cellWidth
                        height: wallGrid.cellHeight
                        Column {
                            anchors { fill: parent; margins: 4 }
                            spacing: 4
                            ClippingRectangle {
                                width: parent.width; height: 96; radius: 12
                                border.color: root.isCurrent(modelData.url) ? root.theme.fg : "transparent"
                                border.width: root.isCurrent(modelData.url) ? 2 : 0
                                Image {
                                    anchors.fill: parent
                                    source: modelData.thumb || modelData.url
                                    sourceSize.width: 320; sourceSize.height: 180
                                    asynchronous: true; cache: true; smooth: true; mipmap: true
                                    fillMode: Image.PreserveAspectCrop
                                }
                                Rectangle {
                                    anchors { left: parent.left; top: parent.top; margins: 6 }
                                    visible: root.isCurrent(modelData.url)
                                    radius: 5; color: Qt.alpha(root.theme.bg, 0.7)
                                    width: curTag2.implicitWidth + 10; height: 18
                                    Text {
                                        id: curTag2
                                        anchors.centerIn: parent
                                        text: "当前"
                                        font.family: root.theme.fontFamily; font.pixelSize: 10; color: root.theme.fg
                                    }
                                }
                            }
                            Text {
                                width: parent.width
                                text: root.wallBase(modelData.url)
                                font.family: root.theme.fontFamily; font.pixelSize: 11; color: root.theme.fg
                                elide: Text.ElideRight
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.previewIndex = index
                        }
                    }
                }
            }
        }
    }
}
