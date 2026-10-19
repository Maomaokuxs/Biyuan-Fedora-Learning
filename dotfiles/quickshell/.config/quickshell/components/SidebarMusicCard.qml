import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Widgets

// 边栏音乐卡：B 款唱片沉浸 + C 款底部把手折叠控件
// 配色全部绑定 theme（跟随壁纸取色），无硬编码
ClippingRectangle {
    id: root
    property var theme
    property string songTitle: ""
    property string songArtist: ""
    property string songCover: ""
    property bool musicExpanded: false
    property var player: MprisSelect.pick()

    // theme 快捷别名（带 fallback）
    readonly property color tFg: root.theme ? root.theme.fg : "#f5f5f5"
    readonly property color tMuted: root.theme ? root.theme.muted : "#8a8a8a"
    readonly property color tAccent: root.theme ? root.theme.accent : "#89b4fa"
    readonly property color tCardBg: root.theme ? root.theme.mediaBg : "#26262b"
    readonly property color tBg: root.theme ? root.theme.bg : "#f9f3f1"
    // 封面取色 hex（空 = 取色失败/无封面，回退 theme）
    property string coverBgHex: ""
    property string coverFgHex: ""
    property string coverAccentHex: ""
    property string coverMutedHex: ""
    // 生效色：封面取色优先，失败回退 theme
    readonly property color coverBg: coverBgHex !== "" ? coverBgHex : tCardBg
    readonly property color coverFg: coverFgHex !== "" ? coverFgHex : tFg
    readonly property color coverAccent: coverAccentHex !== "" ? coverAccentHex : tAccent
    readonly property color coverMuted: coverMutedHex !== "" ? coverMutedHex : tMuted
    // accent 实色上的文字色（保证对比度）
    readonly property color coverAccentText: (0.299 * coverAccent.r + 0.587 * coverAccent.g + 0.114 * coverAccent.b) < 0.5 ? "#f5f5f5" : "#1a1a1a"

    function resetCoverPalette() {
        root.coverBgHex = ""; root.coverFgHex = ""; root.coverAccentHex = ""; root.coverMutedHex = "";
    }
    function refreshCoverPalette() {
        var u = String(root.songCover || "");
        if (!u || u.indexOf("data:") === 0) { root.resetCoverPalette(); return; }
        var cmd;
        if (u.indexOf("http://") === 0 || u.indexOf("https://") === 0) {
            var eu = u.replace(/'/g, "'\\''");
            cmd = "curl -sL --max-time 15 -o /tmp/cover-tmp.jpg '" + eu + "' && hellwal --no-cache --skip-term-colors -i /tmp/cover-tmp.jpg -j 2>/dev/null";
        } else {
            var p = u;
            if (p.indexOf("file://") === 0) p = p.slice(7);
            p = p.replace(/'/g, "'\\''");
            cmd = "hellwal --no-cache --skip-term-colors -i '" + p + "' -j 2>/dev/null";
        }
        coverPaletteProc.command = ["bash", "-c", cmd];
        coverPaletteProc.running = true;
    }
    Process {
        id: coverPaletteProc
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
                    root.coverBgHex = bg; root.coverFgHex = fg; root.coverAccentHex = ac; root.coverMutedHex = mu;
                } catch (e) { root.resetCoverPalette(); }
            }
        }
    }
    onSongCoverChanged: root.refreshCoverPalette()
    Component.onCompleted: root.refreshCoverPalette()

    width: 400
    height: 208 + ctrlWrap.height
    radius: 12
    color: coverBg

    // ============ 封面区 208px ============
    Item {
        id: coverItem
        width: parent.width; height: 208

        Image {
            anchors.fill: parent
            source: root.songCover
            visible: root.songCover !== ""
            fillMode: Image.PreserveAspectCrop
            asynchronous: true; cache: true
        }
        Text {
            anchors.centerIn: parent
            text: "♪"
            font.pixelSize: 48; color: Qt.alpha(coverFg, 0.3)
            visible: root.songCover === ""
        }
        // 底部渐变：淡入卡片底色，保证标题可读
        Rectangle {
            width: parent.width; height: 96
            anchors.bottom: parent.bottom
            gradient: Gradient {
                GradientStop { position: 0; color: Qt.alpha(coverBg, 0) }
                GradientStop { position: 1; color: Qt.alpha(coverBg, 0.92) }
            }
        }
        // 标题 + 艺人/歌词
        Column {
            anchors { left: parent.left; right: parent.right; bottom: parent.bottom; margins: 12; rightMargin: 64 }
            spacing: 4
            Text {
                text: root.songTitle || "未播放"
                font.pixelSize: 15; font.bold: true; color: coverFg
                elide: Text.ElideRight; width: parent.width
            }
            Text {
                text: root.songArtist || "Now Playing"
                font.pixelSize: 12; color: Qt.alpha(coverFg, 0.6)
                elide: Text.ElideRight; width: parent.width
            }
        }
        // 右下角 40px 圆形播放按钮
        Rectangle {
            width: 40; height: 40; radius: 20
            anchors { right: parent.right; bottom: parent.bottom; margins: 12 }
            color: coverFg
            Text {
                anchors.centerIn: parent
                text: (root.player && root.player.isPlaying) ? "⏸" : "▶"
                font.pixelSize: 15; color: coverBg
            }
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    var p = MprisSelect.pick();
                    if (p && p.canTogglePlaying) p.togglePlaying();
                }
            }
        }
        // C 款把手：底部中央
        Rectangle {
            width: 40; height: 5; radius: 2.5
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom; bottomMargin: 5 }
            color: Qt.alpha(coverFg, 0.4)
        }
        MouseArea {
            width: 120; height: 20
            anchors { horizontalCenter: parent.horizontalCenter; bottom: parent.bottom }
            onClicked: root.musicExpanded = !root.musicExpanded
        }
    }

    // ============ 可折叠控件区 ============
    Item {
        id: ctrlWrap
        width: parent.width
        anchors.top: coverItem.bottom
        height: root.musicExpanded ? ctrlCol.implicitHeight : 0
        clip: true
        Behavior on height { NumberAnimation { duration: 250 } }

        Column {
            id: ctrlCol
            x: 12; width: parent.width - 24; spacing: 12
            Item { width: 1; height: 4 }

            // ---- 开关行：音乐模块 ----
            Rectangle {
                width: parent.width; height: 36; radius: 10
                color: Qt.alpha(coverAccent, 0.18)
                Text {
                    text: "音乐模块"
                    font.pixelSize: 13; color: coverFg
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                }
                // 开关 48×28
                Rectangle {
                    width: 48; height: 28; radius: 14
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: !BarState.flagM ? coverAccent : Qt.alpha(coverAccent, 0.18)
                    Rectangle {
                        width: 20; height: 20; radius: 10
                        x: !BarState.flagM ? 24 : 4; y: 4
                        color: coverFg
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Exec.sh("bash " + Quickshell.env("HOME") + "/.config/quickshell/scripts/toggle-music.sh");
                            BarState.refresh();
                        }
                    }
                }
            }

            // ---- 开关行：播放键/歌词 ----
            Rectangle {
                width: parent.width; height: 36; radius: 10
                color: Qt.alpha(coverAccent, 0.18)
                Text {
                    text: "播放键/歌词"
                    font.pixelSize: 13; color: coverFg
                    anchors { left: parent.left; leftMargin: 14; verticalCenter: parent.verticalCenter }
                }
                Rectangle {
                    width: 48; height: 28; radius: 14
                    anchors { right: parent.right; rightMargin: 12; verticalCenter: parent.verticalCenter }
                    color: !BarState.flagT ? coverAccent : Qt.alpha(coverAccent, 0.18)
                    Rectangle {
                        width: 20; height: 20; radius: 10
                        x: !BarState.flagT ? 24 : 4; y: 4
                        color: coverFg
                        Behavior on x { NumberAnimation { duration: 150 } }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            Exec.sh("bash " + Quickshell.env("HOME") + "/.config/quickshell/scripts/toggle-music-tail.sh");
                            BarState.refresh();
                        }
                    }
                }
            }

            // ---- 音效组 ----
            Column {
                width: parent.width; spacing: 8
                Row {
                    width: parent.width; spacing: 8
                    Text {
                        text: "音效"
                        font.pixelSize: 13; font.bold: true; color: coverFg
                        anchors.verticalCenter: parent.verticalCenter
                    }
                    Text {
                        text: "作用于顶栏律动效果"
                        font.pixelSize: 11; color: Qt.alpha(coverFg, 0.45)
                        anchors.verticalCenter: parent.verticalCenter
                    }
                }
                // 三段：律动 / 声谱 / 关闭
                Row {
                    width: parent.width; spacing: 8
                    Repeater {
                        model: [
                            { id: "dance", name: "律动" },
                            { id: "spectrum", name: "声谱" },
                            { id: "off", name: "关闭" }
                        ]
                        Rectangle {
                            required property var modelData
                            width: (parent.width - 16) / 3; height: 34; radius: 9
                            color: UiState.vizEffect === modelData.id ? coverAccent : Qt.alpha(coverAccent, 0.18)
                            Text {
                                anchors.centerIn: parent
                                text: modelData.name
                                font.pixelSize: 13
                                color: UiState.vizEffect === modelData.id ? coverAccentText : coverFg
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    UiState.vizEffect = modelData.id;
                                    UiState.vizEffectAutoOff = false;
                                    Exec.sh("printf '" + modelData.id + "' > " + Quickshell.env("HOME") + "/.cache/by-mgr/qs-vizeffect");
                                }
                            }
                        }
                    }
                }
                // 律动图案 Grid（仅律动时可见）
                Grid {
                    width: parent.width; columns: 3
                    rowSpacing: 8; columnSpacing: 8
                    visible: UiState.vizEffect === "dance"
                    Repeater {
                        model: ["竖条", "波纹", "圆点", "同心圆", "方格", "星芒"]
                        Rectangle {
                            required property string modelData
                            required property int index
                            width: (parent.width - 16) / 3; height: 32; radius: 8
                            color: UiState.dancePattern === index ? coverAccent : Qt.alpha(coverAccent, 0.18)
                            Text {
                                anchors.centerIn: parent
                                text: modelData
                                font.pixelSize: 12
                                color: UiState.dancePattern === index ? coverAccentText : coverFg
                            }
                            MouseArea {
                                anchors.fill: parent
                                onClicked: {
                                    UiState.dancePattern = index;
                                    Exec.sh("printf '%s' " + index + " > " + Quickshell.env("HOME") + "/.cache/by-mgr/qs-dancepattern");
                                }
                            }
                        }
                    }
                }
            }
            Item { width: 1; height: 8 }
        }
    }
}
