//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Services.Mpris
import Quickshell.Services.Pipewire
import Quickshell.Services.SystemTray
import Quickshell.Widgets

// duo v2 · 双岛对开（线上功能集成版）：
// 左岛 = 启动＋工作区＋开关组（主题/护眼/熄屏抑制/性能），
// 中央歌词岛独占空位（宽跟内容走，超长截断，两岛长度不再跳动），
// 右岛 = 音乐组（歌名/音律/播放键）＋音量亮度（滚轮调）＋
//       信息组（更新/天气/电池）＋时钟。中央留白露壁纸。
// 配色跟壁纸走（hellwal 中央库），读不到回落苔藓绿。
// 自包含素材：不 import 线上目录；数据走线上脚本绝对路径＋系统服务。
// 预览：先停线上栏（pkill -x quickshell），再 quickshell -p <本目录>。
ShellRoot {
    // ---- 数据层 ----
    Item {
        id: lab
        visible: false
        property color cBg: "#1a2019"
        property color cFg: "#d8e2d0"
        property color cAccent: "#a3be8c"
        property color cMuted: "#5c6656"
        property string font: "JetBrainsMono Nerd Font"
        property string shRoot: "/home/biyuan/.config/quickshell/scripts"
        property string niriScripts: "/home/biyuan/.config/niri/scripts"
        property var now: new Date()
        Timer { interval: 1000; running: true; repeat: true; onTriggered: lab.now = new Date() }
        FileView {
            id: palView
            path: "/home/biyuan/.cache/by-mgr/hellwal/global-palette.env"
            onLoaded: lab.applyPalette(palView.text())
        }
        Timer {
            interval: 5000; running: true; repeat: true
            onTriggered: palView.reload()
        }
        function applyPalette(t) {
            try {
                var m = {}, re = /^([A-Z_]+)="([^"]*)"/gm, mt;
                while ((mt = re.exec(t)) !== null)
                    m[mt[1]] = mt[2];
                if (m.BG)
                    lab.cBg = m.BG;
                if (m.FG)
                    lab.cFg = m.FG;
                if (m.ACCENT)
                    lab.cAccent = m.ACCENT;
                if (m.MUTED)
                    lab.cMuted = m.MUTED;
            } catch (e) {}
        }
        // 聚合文本：开关组＋歌词＋亮度＋左侧小工具
        property string gammaT: ""
        property string themeT: ""
        property string inhibitT: ""
        property string ppT: ""
        property string lyricT: ""
        property string briT: ""
        property string recT: ""
        property string shotT: ""
        property string pickT: ""
        property string clipT: ""
        property string screenT: ""
        Process {
            running: true
            command: [lab.shRoot + "/bar-fast.sh"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    try {
                        var o = JSON.parse(data);
                        lab.gammaT = (o.gamma && o.gamma.text) || "";
                        lab.themeT = (o.theme && o.theme.text) || "";
                        lab.inhibitT = (o.inhibit && o.inhibit.text) || "";
                        lab.ppT = (o.pp && o.pp.text) || "";
                        lab.lyricT = (o.lyric && o.lyric.text) || "";
                        lab.briT = (o.bri && o.bri.text) || "";
                    } catch (e) {}
                }
            }
        }
        // 小工具直调：FORCE_SHOW=1 无视 flagL 常显（聚合输出只给线上栏，不动它）
        function applyTool(key, data) {
            try {
                var j = JSON.parse(data);
                lab[key] = j.text || "";
            } catch (e) {}
        }
        Process {
            id: recProc
            command: ["bash", "-c", "FORCE_SHOW=1 " + lab.shRoot + "/left-visibility.sh F044A"]
            stdout: StdioCollector { onStreamFinished: lab.applyTool("recT", text) }
        }
        Process {
            id: shotProc
            command: ["bash", "-c", "FORCE_SHOW=1 " + lab.shRoot + "/left-visibility.sh F030"]
            stdout: StdioCollector { onStreamFinished: lab.applyTool("shotT", text) }
        }
        Process {
            id: pickProc
            command: ["bash", "-c", "FORCE_SHOW=1 " + lab.shRoot + "/left-visibility.sh F1FB"]
            stdout: StdioCollector { onStreamFinished: lab.applyTool("pickT", text) }
        }
        Process {
            id: clipProc
            command: ["bash", "-c", "FORCE_SHOW=1 " + lab.shRoot + "/left-visibility.sh F0EA"]
            stdout: StdioCollector { onStreamFinished: lab.applyTool("clipT", text) }
        }
        Process {
            id: screenProc
            command: [lab.shRoot + "/common/screen.sh"]
            stdout: StdioCollector { onStreamFinished: lab.applyTool("screenT", text) }
        }
        Timer {
            interval: 2000; running: true; repeat: true
            onTriggered: { recProc.running = true; shotProc.running = true; pickProc.running = true; clipProc.running = true; screenProc.running = true; }
        }
        // 工作区
        property var wsList: []
        Process {
            id: wsProc
            command: ["niri", "msg", "-j", "workspaces"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var arr = JSON.parse(text);
                        arr.sort(function (a, b) { return a.idx - b.idx; });
                        var out = [];
                        for (var i = 0; i < arr.length; i++) {
                            // dock 最小化收纳用的隐藏工作区不显示（和线上 Workspaces 一致）
                            if (arr[i].name === "__dockmin__")
                                continue;
                            out.push({ idx: arr[i].idx, output: arr[i].output || "", active: (arr[i].is_active === true || arr[i].is_focused === true) });
                        }
                        lab.wsList = out;
                    } catch (e) {}
                }
            }
        }
        Timer { interval: 5000; running: true; repeat: true; onTriggered: wsProc.running = true }
        // 事件驱动即时刷新：niri 任何事件都可能伴随工作区变化，来一条刷一次；
        // 1s 轮询太慢（点完等半天才动=卡），5s 只留作兜底
        Process {
            running: true
            command: ["niri", "msg", "--json", "event-stream"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    if (String(data).indexOf("Workspace") >= 0 && !wsProc.running)
                        wsProc.running = true;
                }
            }
        }
        Process { id: runProc }
        function runCmd(arr) {
            runProc.command = arr;
            runProc.running = true;
        }
        // 风格切换菜单：_absolute 路径调 bar-lab 的 qs-switch（风格除 duo 外都在那边）
        property bool styleMenuOpen: false
        property string qsSwitch: "/home/biyuan/Documents/quickshell/bar-lab/qs-switch.sh"
        function styleGo(name) {
            lab.styleMenuOpen = false;
            lab.runCmd(["bash", lab.qsSwitch, name]);
        }
        function wsFocus(idx, output) {
            // 乐观 UI：先本地点亮，不等事件回包（错了下次刷新纠正）
            try {
                var cur = lab.wsList;
                var out = [];
                for (var i = 0; i < cur.length; i++)
                    out.push({ idx: cur[i].idx, output: cur[i].output, active: cur[i].idx === idx && (output === undefined || cur[i].output === output) });
                lab.wsList = out;
            } catch (e) {}
            lab.runCmd(["niri", "msg", "action", "focus-workspace", String(idx)]);
        }
        // 风格表：只要 default / duo 两套
        property var styleNames: ["default", "duo"]
        // 播放器＋音量（同一秒轮询，省一个 Timer）
        property bool playing: false
        property string songT: ""
        property int volPct: 0
        property bool volMuted: false
        Timer {
            interval: 1000; running: true; repeat: true
            onTriggered: {
                var playing = false, txt = "", p = null;
                try {
                    var vs = Mpris.players.values;
                    var i;
                    for (i = 0; i < vs.length; i++) {
                        try { if (vs[i].valid !== false && vs[i].isPlaying) { p = vs[i]; break; } } catch (e) {}
                    }
                    if (!p) {
                        for (i = 0; i < vs.length; i++) {
                            try { if (vs[i].valid !== false) { p = vs[i]; break; } } catch (e2) {}
                        }
                    }
                    if (p) {
                        playing = !!p.isPlaying;
                        var t = p.trackTitle || "", a = p.trackArtist || "";
                        var full = a !== "" ? t + " - " + a : t;
                        txt = full.length <= 18 ? full : full.slice(0, 15) + "...";
                        if (txt !== "")
                            txt = (playing ? "♪ " : "❚❚ ") + txt;
                    }
                } catch (e3) {}
                lab.playing = playing;
                lab.songT = txt;
                try {
                    var s = Pipewire.ready ? Pipewire.defaultAudioSink : null;
                    if (s && s.ready && s.audio) {
                        lab.volPct = Math.round(s.audio.volume * 100);
                        lab.volMuted = !!s.audio.muted;
                    }
                } catch (e4) {}
            }
        }
        function volAdjust(d) {
            try {
                var s = Pipewire.ready ? Pipewire.defaultAudioSink : null;
                if (s && s.ready && s.audio) {
                    if (s.audio.muted)
                        s.audio.muted = false;
                    s.audio.volume = Math.max(0, Math.min(1, s.audio.volume + d));
                }
            } catch (e) {}
        }
        function volMute() {
            try {
                var s = Pipewire.ready ? Pipewire.defaultAudioSink : null;
                if (s && s.ready && s.audio)
                    s.audio.muted = !s.audio.muted;
            } catch (e) {}
        }
        // shell 单引号转义（托盘标题里什么引号都有）
        function shQ(s) {
            return "'" + String(s || "").replace(/'/g, "'\\''") + "'";
        }
        function trayOpen(id, title, tooltip) {
            lab.runCmd(["python3", lab.shRoot + "/common/tray-open.py", lab.shQ(id), lab.shQ(title), lab.shQ(tooltip)]);
        }
        // 频谱：播才跑
        property var bands: []
        Process {
            running: lab.playing
            command: [lab.shRoot + "/spectrum.py"]
            stdout: SplitParser {
                splitMarker: "\n"
                onRead: data => {
                    try {
                        var parts = String(data).trim().split(";");
                        if (parts.length < 8)
                            return;
                        var v = [];
                        for (var i = 0; i < parts.length && i < 12; i++) {
                            var n = parseFloat(parts[i]);
                            v.push(isNaN(n) ? 0 : Math.max(0, Math.min(1, n)));
                        }
                        lab.bands = v;
                    } catch (e) {}
                }
            }
        }
        // 更新 / 天气（慢轮询）
        property string updatesT: ""
        Process {
            id: updatesProc
            command: [lab.shRoot + "/common/check-updates.sh"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var j = JSON.parse(text);
                        lab.updatesT = j.text || "";
                    } catch (e) {}
                }
            }
        }
        property string weatherT: ""
        Process {
            id: weatherProc
            command: ["python3", lab.shRoot + "/common/weather.py"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var j = JSON.parse(text);
                        lab.weatherT = j.text || "";
                    } catch (e) {}
                }
            }
        }
        Timer { interval: 1800000; running: true; repeat: true; onTriggered: { updatesProc.running = true; weatherProc.running = true; } }
        Component.onCompleted: { updatesProc.running = true; weatherProc.running = true; }
        // 电池（60s）
        property string batT: ""
        Process {
            id: batProc
            command: ["bash", "-c", "c=$(cat /sys/class/power_supply/BAT0/capacity 2>/dev/null); s=$(cat /sys/class/power_supply/BAT0/status 2>/dev/null); [ -n \"$c\" ] && echo \"$( [ \"$s\" = Charging ] && echo ⚡)${c}%\""]
            stdout: StdioCollector {
                onStreamFinished: { lab.batT = String(text).trim(); }
            }
        }
        Timer { interval: 60000; running: true; repeat: true; onTriggered: batProc.running = true }
    }

    // ---- 对开双岛 ----
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: barWin
            required property var modelData
            screen: modelData
            // 本屏工作区：不过滤会把别屏同 idx 显示出来，高亮错位（线上同款逻辑）
            property var myWs: lab.wsList.filter(function (w) { return !w.output || w.output === modelData.name || modelData.name === ""; })
            anchors { top: true; left: true; right: true }
            margins { top: 6; left: 0; right: 0; bottom: 0 }
            // 日常使用要占位（和线上栏同样 46 高，切换不跳窗口）；
            // 当素材和线上栏叠跑预览时再改回 Ignore
            exclusionMode: ExclusionMode.Auto
            exclusiveZone: 46
            implicitHeight: 46
            color: "transparent"

            // 左岛：启动＋工作区＋开关组（宽跟内容走，动画顺滑不断跳）
            Rectangle {
                anchors { left: parent.left; leftMargin: 14; top: parent.top }
                height: 40
                width: leftRow.implicitWidth + 32
                radius: 20
                color: Qt.alpha(lab.cBg, 0.92)
                border.width: 1
                border.color: Qt.alpha(lab.cAccent, 0.55)
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Row {
                    id: leftRow
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        text: "❀"; font.pixelSize: 17
                        font.family: lab.font
                        color: launchHover.containsMouse ? lab.cFg : lab.cAccent
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            id: launchHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: lab.runCmd(["rofi", "-show", "drun"])
                        }
                    }
                    Row {
                        spacing: 6
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            id: wsRepeater
                            model: myWs
                            Rectangle {
                                required property var modelData
                                width: modelData.active ? 24 : 12; height: 12; radius: 6
                                color: modelData.active ? lab.cAccent : (wsHover.containsMouse ? lab.cFg : lab.cMuted)
                                scale: modelData.active ? 1.15 : 1.0
                                anchors.verticalCenter: parent.verticalCenter
                                Behavior on width { NumberAnimation { duration: 450; easing.type: Easing.InOutCubic } }
                                Behavior on color { ColorAnimation { duration: 450 } }
                                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutBack } }
                                MouseArea {
                                    id: wsHover
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    onClicked: lab.wsFocus(parent.modelData.idx, parent.modelData.output)
                                }
                            }
                        }
                    }
                    Rectangle { width: 1; height: 20; color: Qt.alpha(lab.cMuted, 0.7); anchors.verticalCenter: parent.verticalCenter }
                    // 小工具组：录屏 / 截图 / 取色 / 剪贴板 / 显示器（线上同款动作）
                    Text {
                        text: lab.recT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd(["bash", "/home/biyuan/.config/rofi/scripts/recorder.sh"]) }
                    }
                    Text {
                        text: lab.shotT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd([lab.shRoot + "/common/screenshot.sh"]) }
                    }
                    Text {
                        text: lab.pickT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd([lab.shRoot + "/common/pick-color.sh"]) }
                    }
                    Text {
                        text: lab.clipT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd(["copyq", "toggle"]) }
                    }
                    Text {
                        text: lab.screenT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd([lab.shRoot + "/common/screen.sh", "menu"]) }
                    }
                    // 开关组：主题 / 护眼 / 熄屏抑制 / 性能
                    Text {
                        text: lab.themeT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd(["bash", lab.niriScripts + "/toggle-theme.sh"]) }
                    }
                    Text {
                        text: lab.gammaT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            onClicked: lab.runCmd(["bash", "-c", "pkill gammastep && notify-send 护眼 已关闭 || (gammastep -O 4500 & notify-send 护眼 已开启)"]);
                        }
                    }
                    Text {
                        text: lab.inhibitT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd([lab.shRoot + "/common/inhibit.sh", "toggle"]) }
                    }
                    Text {
                        text: lab.ppT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 15; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.runCmd([lab.shRoot + "/common/powerprofiles.sh", "toggle"]) }
                    }
                    // 壁纸：左键随机一张，右键开图库（线上栏同款）
                    Text {
                        text: "\uF03E"; font.pixelSize: 15
                        font.family: lab.font; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    lab.runCmd(["waypaper"]);
                                else
                                    lab.runCmd(["bash", lab.niriScripts + "/wallpaper.sh"]);
                            }
                        }
                    }
                    // 风格切换菜单入口（漆刷图标，和其它小工具同色）
                    Text {
                        text: "\uF1FC"; font.pixelSize: 15
                        font.family: lab.font; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea { anchors.fill: parent; onClicked: lab.styleMenuOpen = !lab.styleMenuOpen; }
                    }
                        }
                    }
            // 中央歌词岛：独占中央空位，超 40 字截断；
            // 和左右岛互不顶位，歌词跳动不再改变两岛长度
            Rectangle {
                anchors { horizontalCenter: parent.horizontalCenter; top: parent.top }
                height: 40
                width: lyricRow.implicitWidth + 40
                radius: 20
                visible: lab.lyricT !== ""
                color: Qt.alpha(lab.cBg, 0.92)
                border.width: 1
                border.color: Qt.alpha(lab.cAccent, 0.55)
                Behavior on width { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
                Row {
                    id: lyricRow
                    anchors.centerIn: parent
                    Text {
                        text: lab.lyricT.length > 40 ? lab.lyricT.slice(0, 40) + "…" : lab.lyricT
                        font.family: lab.font; font.pixelSize: 14; color: lab.cMuted
                    }
                }
            }
            // 右岛：音乐组＋音量亮度＋信息组＋时钟
            // 右岛（宽跟内容走，同左岛顺滑）
            Rectangle {
                anchors { right: parent.right; rightMargin: 14; top: parent.top }
                height: 40
                width: rightRow.implicitWidth + 32
                radius: 20
                color: Qt.alpha(lab.cBg, 0.92)
                border.width: 1
                border.color: Qt.alpha(lab.cAccent, 0.55)
                Behavior on width { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
                Row {
                    id: rightRow
                    anchors.centerIn: parent
                    spacing: 10
                    Text {
                        text: lab.songT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 14; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            acceptedButtons: Qt.LeftButton | Qt.RightButton
                            onClicked: mouse => {
                                if (mouse.button === Qt.RightButton)
                                    lab.runCmd(["playerctl", "next"]);
                                else
                                    lab.runCmd(["playerctl", "play-pause"]);
                            }
                        }
                    }
                    Row {
                        spacing: 2; visible: lab.playing
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: 12
                            Rectangle {
                                required property int index
                                property real v: lab.bands.length > index ? lab.bands[index] : 0
                                width: 4; height: Math.max(3, Math.min(1, v) * 20)
                                radius: 2
                                color: lab.cAccent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                    }
                    // 播放键胶囊（大一号好点）
                    Rectangle {
                        height: 28
                        width: mprisRow.implicitWidth + 26
                        radius: 14
                        color: Qt.alpha(lab.cAccent, 0.28)
                        anchors.verticalCenter: parent.verticalCenter
                        Row {
                            id: mprisRow
                            anchors.centerIn: parent
                            spacing: 12
                            Text {
                                text: "\uF048"; font.pixelSize: 16
                                font.family: lab.font; color: lab.cFg
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; onClicked: lab.runCmd(["playerctl", "previous"]) }
                            }
                            Text {
                                text: lab.playing ? "\uF04C" : "\uF04B"; font.pixelSize: 17
                                font.family: lab.font; color: lab.cFg
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; onClicked: lab.runCmd(["playerctl", "play-pause"]) }
                            }
                            Text {
                                text: "\uF051"; font.pixelSize: 16
                                font.family: lab.font; color: lab.cFg
                                anchors.verticalCenter: parent.verticalCenter
                                MouseArea { anchors.fill: parent; onClicked: lab.runCmd(["playerctl", "next"]) }
                            }
                        }
                    }
                    Rectangle { width: 1; height: 20; color: Qt.alpha(lab.cMuted, 0.7); anchors.verticalCenter: parent.verticalCenter }
                    // 音量（点静音＋滚轮）
                    Text {
                        text: (lab.volMuted ? "󰝟 " : " ") + lab.volPct + "%"
                        font.family: lab.font; font.pixelSize: 14; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            onClicked: lab.volMute()
                        }
                        WheelHandler {
                            onWheel: event => {
                                lab.volAdjust(event.angleDelta.y > 0 ? 0.05 : -0.05);
                                event.accepted = true;
                            }
                        }
                    }
                    // 亮度（滚轮＋点回中）
                    Text {
                        text: lab.briT !== "" ? lab.briT : "󰃟 --"
                        font.family: lab.font; font.pixelSize: 14; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                        MouseArea {
                            anchors.fill: parent
                            onClicked: lab.runCmd([lab.shRoot + "/brightness.sh", "mid"])
                        }
                        WheelHandler {
                            onWheel: event => {
                                lab.runCmd([lab.shRoot + "/brightness.sh", event.angleDelta.y > 0 ? "up" : "down"]);
                                event.accepted = true;
                            }
                        }
                    }
                    Rectangle { width: 1; height: 20; color: Qt.alpha(lab.cMuted, 0.7); anchors.verticalCenter: parent.verticalCenter }
                    // 信息组：更新 / 天气 / 电池
                    Text {
                        text: lab.updatesT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 14; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: lab.weatherT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 14; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: lab.batT; visible: text !== ""
                        font.family: lab.font; font.pixelSize: 14; color: lab.cFg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    // 托盘：线上同款左键通用链＋右键菜单（图标可能是主题名，必须 IconImage）
                    Row {
                        spacing: 2
                        anchors.verticalCenter: parent.verticalCenter
                        Repeater {
                            model: SystemTray.items.values
                            MouseArea {
                                id: trayMouse
                                width: 24; height: 28
                                acceptedButtons: Qt.LeftButton | Qt.RightButton
                                onClicked: e => {
                                    if (e.button === Qt.LeftButton) {
                                        if (modelData.onlyMenu && modelData.hasMenu)
                                            trayMenu.open();
                                        else
                                            lab.trayOpen(modelData.id, modelData.title, modelData.tooltipTitle);
                                    } else {
                                        if (modelData.hasMenu)
                                            trayMenu.open();
                                        else
                                            modelData.secondaryActivate();
                                    }
                                }
                                QsMenuAnchor {
                                    id: trayMenu
                                    anchor.window: barWin
                                    anchor.item: trayMouse
                                    anchor.edges: Edges.Bottom
                                    anchor.gravity: Edges.Bottom
                                    menu: modelData.menu
                                }
                                IconImage {
                                    anchors.centerIn: parent
                                    implicitSize: 19
                                    source: modelData.icon
                                }
                            }
                        }
                    }
                    Text {
                        text: Qt.formatDateTime(lab.now, "hh:mm")
                        font.family: lab.font; font.pixelSize: 16; font.bold: true; color: lab.cAccent
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
            }
        }
    }

    // ---- 风格切换弹窗：全屏透明窗＋居中卡，点名即切（qs-switch），点空白处关 ----
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: lab.styleMenuOpen
            anchors { top: true; bottom: true; left: true; right: true }
            exclusionMode: ExclusionMode.Ignore
            color: "transparent"

            MouseArea {
                anchors.fill: parent
                onClicked: lab.styleMenuOpen = false
            }
            Rectangle {
                anchors.centerIn: parent
                width: 380
                height: menuCol.implicitHeight + 36
                radius: 18
                color: Qt.alpha(lab.cBg, 0.97)
                border.width: 1
                border.color: Qt.alpha(lab.cAccent, 0.6)
                MouseArea {
                    anchors.fill: parent
                    onClicked: mouse => mouse.accepted = true
                }
                Column {
                    id: menuCol
                    anchors { top: parent.top; left: parent.left; right: parent.right; margins: 18; topMargin: 16 }
                    spacing: 10
                    Row {
                        width: parent.width
                        height: 24
                        Text {
                            text: "切换风格"
                            font.family: lab.font; font.pixelSize: 15; font.bold: true
                            color: lab.cFg
                            anchors.verticalCenter: parent.verticalCenter
                        }
                    }
                    Grid {
                        width: parent.width
                        columns: 3
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: lab.styleNames
                            Rectangle {
                                required property string modelData
                                width: (344 - 16) / 3; height: 34; radius: 10
                                color: "transparent"
                                border.width: 1
                                border.color: lab.cMuted
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    font.family: lab.font; font.pixelSize: 13
                                    color: lab.cFg
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: lab.styleGo(parent.modelData)
                                }
                            }
                        }
                    }
                    Text {
                        text: "点名即切（旧实例先退），点空白处关闭"
                        font.family: lab.font; font.pixelSize: 11
                        color: lab.cMuted
                    }
                }
            }
        }
    }
}
