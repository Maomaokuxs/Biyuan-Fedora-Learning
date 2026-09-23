import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// 控制中心 overlay 卡：rofi 做不了的三件套——
// 多标签常驻（顶栏/主题/音律/音乐）、滑杆（音量/亮度）、开关实时状态位。
// 动作层全部复用线上脚本（toggle-bar 系/toggle-theme/toggle-music 系），
// 和键位保持同源，不另起契约。
// 注：lab 风格路径写死 ~/Documents（用户要求风格不进主仓库，代价在此）。
Item {
    id: root
    property var theme
    signal requestClose

    implicitWidth: 460
    implicitHeight: 470

    property string page: "bar" // bar|theme|viz|music
    property string labRoot: "/home/biyuan/Documents/quickshell/bar-lab"

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
        clip: true

        Column {
            anchors { fill: parent; margins: 14 }
            spacing: 10

            // 标题行
            Item {
                width: parent.width
                height: 28
                Text {
                    text: "控制中心"
                    font.family: root.theme.fontFamily; font.pixelSize: 15; font.bold: true
                    color: root.theme.fg
                    anchors { left: parent.left; verticalCenter: parent.verticalCenter }
                }
                Text {
                    anchors { right: parent.right; rightMargin: 4; verticalCenter: parent.verticalCenter }
                    text: "✕"
                    font.pixelSize: 13
                    color: root.theme.muted
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -8
                        onClicked: root.requestClose()
                    }
                }
            }

            // 标签行
            Row {
                width: parent.width
                height: 34
                spacing: 8
                Repeater {
                    model: [
                        { id: "bar", name: "顶栏" },
                        { id: "theme", name: "主题" },
                        { id: "viz", name: "音律" },
                        { id: "music", name: "音乐" }
                    ]
                    Rectangle {
                        required property var modelData
                        width: (parent.width - 24) / 4; height: 34; radius: 10
                        color: root.page === modelData.id ? root.theme.accent : "transparent"
                        border.width: 1
                        border.color: root.page === modelData.id ? "transparent" : root.theme.muted
                        Text {
                            anchors.centerIn: parent
                            text: parent.modelData.name
                            font.family: root.theme.fontFamily; font.pixelSize: 13
                            font.bold: root.page === parent.modelData.id
                            color: root.page === parent.modelData.id ? root.theme.bg : root.theme.fg
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: root.page = parent.modelData.id
                        }
                    }
                }
            }

            // ---- 顶栏页 ----
            Item {
                id: barPage
                width: parent.width
                height: 360
                visible: root.page === "bar"
                property string current: ""
                function detect() {
                    detectProc.running = true;
                }
                onVisibleChanged: { if (visible) barPage.detect(); }
                Component.onCompleted: barPage.detect()
                Process {
                    id: detectProc
                    command: ["bash", "-c", "pgrep -x waybar >/dev/null && echo WAYBAR || pgrep -af '^quickshell -p' | head -n 1"]
                    stdout: StdioCollector {
                        onStreamFinished: {
                            var t = String(text).trim();
                            if (t === "WAYBAR") {
                                barPage.current = "waybar";
                                return;
                            }
                            var m = /-p (\S+)/.exec(t);
                            if (m) {
                                var d = m[1];
                                if (d === "/home/biyuan/.config/quickshell")
                                    barPage.current = "live";
                                else
                                    barPage.current = d.split("/").pop();
                            }
                        }
                    }
                }
                function launch(id) {
                    if (id === "waybar") {
                        Exec.sh("pkill -x quickshell; pkill waybar 2>/dev/null; pkill cava 2>/dev/null; waybar & disown");
                    } else if (id === "live") {
                        Exec.sh("pkill waybar 2>/dev/null; pkill -x quickshell; systemctl --user stop mako 2>/dev/null; pkill -x mako 2>/dev/null; quickshell -p /home/biyuan/.config/quickshell -d -n & disown");
                    } else {
                        Exec.sh("pkill -x quickshell; sleep 0.5; quickshell -p " + root.labRoot + "/" + id + " -d -n & disown");
                    }
                }
                Column {
                    anchors.fill: parent
                    spacing: 8
                    Text {
                        text: barPage.current === "" ? "当前：…" : "当前：" + barPage.current
                        font.family: root.theme.fontFamily; font.pixelSize: 12
                        color: root.theme.muted
                    }
                    Grid {
                        width: parent.width
                        columns: 4
                        columnSpacing: 8
                        rowSpacing: 8
                        Repeater {
                            model: ["waybar", "live", "duo", "decker", "notch", "caelestia", "frame", "material", "noctalia", "bottom", "capsules", "tabs"]
                            Rectangle {
                                required property string modelData
                                width: (parent.width - 24) / 4; height: 32; radius: 9
                                color: barPage.current === modelData ? root.theme.accent : "transparent"
                                border.width: 1
                                border.color: barPage.current === modelData ? "transparent" : root.theme.muted
                                Text {
                                    anchors.centerIn: parent
                                    text: parent.modelData
                                    font.family: root.theme.fontFamily; font.pixelSize: 12
                                    color: barPage.current === parent.modelData ? root.theme.bg : root.theme.fg
                                }
                                MouseArea {
                                    anchors.fill: parent
                                    onClicked: barPage.launch(parent.modelData)
                                }
                            }
                        }
                    }
                    Text {
                        text: "切栏后本面板随旧实例退出，新栏即时接管"
                        font.family: root.theme.fontFamily; font.pixelSize: 11
                        color: root.theme.muted
                    }
                }
            }

            // ---- 主题页 ----
            Item {
                width: parent.width
                height: 360
                visible: root.page === "theme"
                Column {
                    anchors.fill: parent
                    spacing: 10
                    // 昼夜切换
                    Rectangle {
                        width: parent.width; height: 44; radius: 10
                        color: Qt.alpha(root.theme.accent, 0.25)
                        Row {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            spacing: 8
                            Text {
                                text: "昼夜"
                                font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                color: root.theme.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: BarState.themeT !== "" ? BarState.themeT : "…"
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                                color: root.theme.muted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 1; height: 1 }
                            Text {
                                text: "切换"
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                                color: root.theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Exec.sh("bash /home/biyuan/.config/niri/scripts/toggle-theme.sh");
                        }
                    }
                    // 随机壁纸
                    Rectangle {
                        width: parent.width; height: 44; radius: 10
                        color: "transparent"
                        border.width: 1
                        border.color: root.theme.muted
                        Row {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            spacing: 8
                            Text {
                                text: "壁纸"
                                font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                color: root.theme.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "随机一张（自动跟色）"
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                                color: root.theme.muted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Exec.sh("bash /home/biyuan/.config/niri/scripts/wallpaper.sh");
                        }
                    }
                    // 壁纸库
                    Rectangle {
                        width: parent.width; height: 44; radius: 10
                        color: "transparent"
                        border.width: 1
                        border.color: root.theme.muted
                        Row {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            spacing: 8
                            Text {
                                text: "图库"
                                font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                color: root.theme.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Text {
                                text: "打开 waypaper 挑选"
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                                color: root.theme.muted
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: Exec.sh("waypaper & disown");
                        }
                    }
                }
            }

            // ---- 音律页 ----
            Item {
                width: parent.width
                height: 360
                visible: root.page === "viz"
                Column {
                    anchors.fill: parent
                    spacing: 10
                    Repeater {
                        model: [
                            { id: "dance", name: "律动", desc: "程序编排跟响度走，零外部进程" },
                            { id: "spectrum", name: "声谱", desc: "pw-record 直采 + FFT，真分频" },
                            { id: "off", name: "关闭", desc: "静默基线，不跑进程" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: parent.width; height: 52; radius: 10
                            color: UiState.vizEffect === modelData.id ? root.theme.accent : "transparent"
                            border.width: 1
                            border.color: UiState.vizEffect === modelData.id ? "transparent" : root.theme.muted
                            Column {
                                anchors { fill: parent; leftMargin: 14; rightMargin: 14; topMargin: 7; bottomMargin: 7 }
                                spacing: 2
                                Text {
                                    text: parent.parent.modelData.name
                                    font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                    color: UiState.vizEffect === parent.parent.modelData.id ? root.theme.bg : root.theme.fg
                                }
                                Text {
                                    text: parent.parent.modelData.desc
                                    font.family: root.theme.fontFamily; font.pixelSize: 11
                                    color: UiState.vizEffect === parent.parent.modelData.id ? root.theme.bg : root.theme.muted
                                }
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    UiState.vizEffect = parent.modelData.id;
                                    UiState.vizEffectAutoOff = false;
                                    Exec.sh("printf '" + parent.modelData.id + "' > /home/biyuan/.cache/by-mgr/qs-vizeffect");
                                }
                            }
                        }
                    }
                    Text {
                        text: UiState.vizEffectAutoOff ? "无音频自动关闭中，来声恢复" : "手动选择即时生效并落盘"
                        font.family: root.theme.fontFamily; font.pixelSize: 11
                        color: root.theme.muted
                    }
                }
            }

            // ---- 音乐页 ----
            Item {
                width: parent.width
                height: 360
                visible: root.page === "music"
                Column {
                    anchors.fill: parent
                    spacing: 10
                    // 音量滑杆（Pipewire 直写）
                    Rectangle {
                        width: parent.width; height: 56; radius: 10
                        color: Qt.alpha(root.theme.accent, 0.18)
                        Row {
                            anchors { fill: parent; margins: 12 }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: volSink.muted ? "󰝟" : (volSink.vol <= 0 ? "" : volSink.vol < 0.6 ? "" : "")
                                font.pixelSize: 17
                                font.family: root.theme.fontFamily
                                color: root.theme.fg
                                MouseArea {
                                    anchors.fill: parent
                                    anchors.margins: -6
                                    onClicked: {
                                        if (volSink.sink && volSink.sink.ready && volSink.sink.audio)
                                            volSink.sink.audio.muted = !volSink.sink.audio.muted;
                                    }
                                }
                            }
                            SliderBar {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24 - 44 - 20 - 20
                                theme: root.theme
                                value01: volSink.vol
                                onMoved: ratio => volSink.setVol(ratio, false)
                                onReleased: ratio => volSink.setVol(ratio, true)
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                text: volSink.muted ? "静音" : Math.round(volSink.vol * 100) + "%"
                                font.pixelSize: 12
                                font.family: root.theme.fontFamily
                                color: root.theme.fg
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    // 亮度滑杆（脚本后端，松手提交）
                    Rectangle {
                        width: parent.width; height: 56; radius: 10
                        color: Qt.alpha(root.theme.accent, 0.18)
                        Row {
                            anchors { fill: parent; margins: 12 }
                            spacing: 10
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                text: "󰃟"
                                font.pixelSize: 17
                                font.family: root.theme.fontFamily
                                color: root.theme.fg
                            }
                            SliderBar {
                                anchors.verticalCenter: parent.verticalCenter
                                width: parent.width - 24 - 44 - 20 - 20
                                theme: root.theme
                                value01: briState.pct / 100
                                enabled: !briState.busy
                                onMoved: ratio => { briState.pct = Math.round(ratio * 100); }
                                onReleased: ratio => { briState.pct = Math.round(ratio * 100); briState.commit(briState.pct); }
                            }
                            Text {
                                anchors.verticalCenter: parent.verticalCenter
                                width: 44
                                text: briState.pct + "%"
                                font.pixelSize: 12
                                font.family: root.theme.fontFamily
                                color: root.theme.fg
                                horizontalAlignment: Text.AlignRight
                            }
                        }
                    }
                    // 音乐总闸
                    Rectangle {
                        width: parent.width; height: 44; radius: 10
                        color: BarState.flagM ? "transparent" : Qt.alpha(root.theme.accent, 0.25)
                        border.width: 1
                        border.color: BarState.flagM ? root.theme.muted : "transparent"
                        Row {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            Text {
                                text: "音乐模块"
                                font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                color: root.theme.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 1; height: 1 }
                            Text {
                                text: BarState.flagM ? "已隐藏" : "显示中"
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                                color: BarState.flagM ? root.theme.muted : root.theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Exec.sh("bash " + Exec.commonDir + "/toggle-music.sh");
                                BarState.refresh();
                            }
                        }
                    }
                    // 跟随者开关
                    Rectangle {
                        width: parent.width; height: 44; radius: 10
                        color: BarState.flagT ? "transparent" : Qt.alpha(root.theme.accent, 0.25)
                        border.width: 1
                        border.color: BarState.flagT ? root.theme.muted : "transparent"
                        Row {
                            anchors { fill: parent; leftMargin: 14; rightMargin: 14 }
                            Text {
                                text: "播放键/歌词"
                                font.family: root.theme.fontFamily; font.pixelSize: 13; font.bold: true
                                color: root.theme.fg
                                anchors.verticalCenter: parent.verticalCenter
                            }
                            Item { width: 1; height: 1 }
                            Text {
                                text: BarState.flagT ? "已隐藏" : "显示中"
                                font.family: root.theme.fontFamily; font.pixelSize: 12
                                color: BarState.flagT ? root.theme.muted : root.theme.accent
                                anchors.verticalCenter: parent.verticalCenter
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                Exec.sh("bash " + Exec.commonDir + "/toggle-music-tail.sh");
                                BarState.refresh();
                            }
                        }
                    }
                }
            }
        }
    }

    // 音量后端（VolCard 同款直写）
    Item {
        id: volSink
        property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
        property real vol: (sink && sink.ready && sink.audio) ? sink.audio.volume : 0
        property bool muted: sink && sink.ready && sink.audio ? sink.audio.muted : false
        function setVol(ratio, commit) {
            var s = volSink.sink;
            if (s && s.ready && s.audio) {
                if (s.audio.muted)
                    s.audio.muted = false;
                s.audio.volume = Math.max(0, Math.min(1, ratio));
            }
        }
    }

    // 亮度后端（BriCard 同款脚本，松手提交）
    Item {
        id: briState
        property int pct: 50
        property bool busy: false
        function refresh() {
            poller.running = true;
        }
        Component.onCompleted: briState.refresh()
        Process {
            id: poller
            command: ["bash", "-c", UiState.briExternal
                ? Exec.scriptDir + "/brightness-external.sh"
                : Exec.scriptDir + "/brightness.sh"]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var j = JSON.parse(this.text);
                        var m = /([0-9]+)%/.exec(j.text || "");
                        if (m)
                            briState.pct = Math.max(0, Math.min(100, parseInt(m[1])));
                    } catch (e) {}
                }
            }
        }
        function commit(v) {
            briState.busy = true;
            setter.command = ["bash", "-c",
                Exec.scriptDir + "/brightness-set.sh "
                + (UiState.briExternal ? "external " : "internal ") + String(v)];
            setter.running = true;
        }
        Process {
            id: setter
            onExited: {
                briState.busy = false;
                refreshTimer.restart();
            }
        }
        Timer {
            id: refreshTimer
            interval: 900
            onTriggered: briState.refresh()
        }
    }
}
