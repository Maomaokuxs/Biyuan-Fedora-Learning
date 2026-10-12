import QtQuick

// 音乐详情抽屉（2026-10-10）：从顶栏胶囊向下展开，显示详细信息。
// 纵向展开动画（scaleY + 淡入），transformOrigin 顶部。
Item {
    id: root
    property var theme
    signal requestClose

    property var player: MprisSelect.pick()
    property string lyric: BarState.lyricT
    property string lyricClass: BarState.lyricC

    property double pos: 0
    property double len: {
        var p = root.player;
        if (!p) return 0;
        if (p.lengthSupported && p.length > 0) return p.length;
        if (p.metadata) {
            var ml = p.metadata["mpris:length"];
            if (ml > 0) return ml / 1000000;
        }
        return 0;
    }
    property double ratio: root.len > 0 ? Math.min(1, root.pos / root.len) : 0
    function syncPos() {
        var p = root.player;
        root.pos = p ? (p.position || 0) : 0;
    }
    Timer {
        interval: 500
        running: root.visible && root.player && root.player.isPlaying
        repeat: true
        onTriggered: {
            root.pos += 0.5;
            if (root.len > 0 && root.pos > root.len) root.pos = root.len;
        }
    }
    Connections {
        target: root.player
        function onTrackTitleChanged() { root.syncPos(); }
        function onPositionChanged() {
            if (root.player && Math.abs(root.player.position - root.pos) > 1.5)
                root.pos = root.player.position;
        }
    }

    width: 320
    height: 300
    implicitWidth: 320
    implicitHeight: 300

    // 向下展开动画
    property bool expanded: false
    scale: expanded ? 1 : 0.92
    opacity: expanded ? 1 : 0
    // 用 y 位移模拟从胶囊垂下
    y: expanded ? 0 : -12
    Behavior on scale { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Behavior on opacity { NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    Behavior on y { NumberAnimation { duration: 240; easing.type: Easing.OutCubic } }
    Component.onCompleted: { root.syncPos(); expanded = true; }
    transformOrigin: Item.Top

    Rectangle {
        anchors.fill: parent
        radius: 18
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
        clip: true

        // ✕ 关闭
        Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 10
            text: "✕"
            font.pixelSize: 12
            color: root.theme.muted
            opacity: 0.7
            z: 2
            MouseArea {
                anchors.fill: parent
                anchors.margins: -8
                hoverEnabled: true
                onEntered: parent.opacity = 1
                onExited: parent.opacity = 0.7
                onClicked: root.requestClose()
            }
        }

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            // 封面 + 基本信息
            Row {
                width: parent.width
                spacing: 12
                Rectangle {
                    width: 72; height: 72
                    radius: 10
                    color: root.theme.accent
                    clip: true
                    Image {
                        anchors.fill: parent
                        source: (root.player && root.player.trackArtUrl) || ""
                        fillMode: Image.PreserveAspectCrop
                        asynchronous: true
                        cache: false
                        smooth: true
                        mipmap: true
                        visible: status === Image.Ready
                    }
                    Text {
                        anchors.centerIn: parent
                        text: Icons.coverFallback
                        font.family: root.theme.fontFamily
                        font.pixelSize: 24
                        color: root.theme.fg
                        visible: !root.player || !root.player.trackArtUrl
                    }
                }
                Column {
                    width: parent.width - 72 - 12 - 20
                    anchors.verticalCenter: parent.verticalCenter
                    spacing: 3
                    Text {
                        width: parent.width
                        text: (root.player && root.player.trackTitle) || "无标题"
                        font.family: root.theme.fontFamily
                        font.pixelSize: 15
                        font.bold: true
                        color: root.theme.fg
                        elide: Text.ElideRight
                        maximumLineCount: 1
                    }
                    Text {
                        width: parent.width
                        text: (root.player && root.player.trackArtist) || ""
                        font.family: root.theme.fontFamily
                        font.pixelSize: 12
                        color: root.theme.muted
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                    Text {
                        width: parent.width
                        text: {
                            var p = root.player;
                            if (!p || !p.metadata) return "";
                            var al = p.metadata["xesam:album"] || "";
                            return al;
                        }
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        color: root.theme.muted
                        opacity: 0.8
                        elide: Text.ElideRight
                        visible: text !== ""
                    }
                }
            }

            // 歌词
            Rectangle {
                width: parent.width
                height: 64
                radius: 10
                color: Qt.alpha(root.theme.muted, 0.12)
                Text {
                    anchors.fill: parent
                    anchors.margins: 10
                    text: root.lyric || "♪"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 15
                    font.bold: true
                    color: root.theme.fg
                    elide: Text.ElideRight
                    maximumLineCount: 2
                    wrapMode: Text.WordWrap
                    verticalAlignment: Text.AlignVCenter
                    horizontalAlignment: Text.AlignHCenter
                }
            }

            // 进度条
            Item {
                width: parent.width
                height: 20
                Rectangle {
                    id: track
                    anchors.verticalCenter: parent.verticalCenter
                    width: parent.width
                    height: 4
                    radius: 2
                    color: Qt.alpha(root.theme.muted, 0.3)
                    Rectangle {
                        width: parent.width * root.ratio
                        height: parent.height
                        radius: 2
                        color: root.theme.accent
                        Behavior on width { NumberAnimation { duration: 200 } }
                    }
                }
                Text {
                    anchors.left: parent.left
                    anchors.bottom: parent.bottom
                    text: {
                        var s = Math.max(0, Math.floor(root.pos));
                        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
                    }
                    font.pixelSize: 10
                    color: root.theme.muted
                    font.family: root.theme.fontFamily
                }
                Text {
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    text: {
                        var s = Math.max(0, Math.floor(root.len));
                        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
                    }
                    font.pixelSize: 10
                    color: root.theme.muted
                    font.family: root.theme.fontFamily
                }
                MouseArea {
                    anchors.fill: parent
                    enabled: (root.player && root.player.positionSupported && root.len > 0) || false
                    onPressed: seek(mouse)
                    onPositionChanged: { if (pressed) seek(mouse); }
                    function seek(m) {
                        var r = Math.max(0, Math.min(1, m.x / track.width));
                        var t = r * root.len;
                        root.pos = t;
                        if (root.player) root.player.position = t;
                    }
                }
            }

            // 控制键
            Row {
                anchors.horizontalCenter: parent.horizontalCenter
                spacing: 16
                Repeater {
                    model: [
                        { icon: Icons.prev, act: "prev" },
                        { icon: "", act: "play" },
                        { icon: Icons.next, act: "next" }
                    ]
                    Item {
                        required property var modelData
                        property bool hovered: false
                        width: modelData.act === "play" ? 44 : 36
                        height: 36
                        Rectangle {
                            anchors.centerIn: parent
                            width: modelData.act === "play" ? 40 : 32
                            height: modelData.act === "play" ? 40 : 32
                            radius: modelData.act === "play" ? 20 : 16
                            color: modelData.act === "play" ? root.theme.accent
                                : (parent.hovered ? Qt.alpha(root.theme.fg, 0.15) : Qt.alpha(root.theme.fg, 0.07))
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: modelData.act === "play"
                                ? ((root.player && root.player.isPlaying) ? Icons.pause : Icons.play)
                                : modelData.icon
                            font.pixelSize: modelData.act === "play" ? 16 : 13
                            font.bold: true
                            font.family: root.theme.fontFamily
                            color: modelData.act === "play" ? root.theme.bg : root.theme.fg
                            opacity: {
                                if (modelData.act === "prev") return (root.player && root.player.canGoPrevious) ? 1 : 0.3;
                                if (modelData.act === "next") return (root.player && root.player.canGoNext) ? 1 : 0.3;
                                return 1;
                            }
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: {
                                var pl = root.player;
                                if (!pl) return;
                                if (modelData.act === "prev" && pl.canGoPrevious) pl.previous();
                                else if (modelData.act === "next" && pl.canGoNext) pl.next();
                                else if (modelData.act === "play") {
                                    if (pl.isPlaying) { if (pl.canTogglePlaying) pl.togglePlaying(); else if (pl.canPause) pl.pause(); }
                                    else { if (pl.canPlay) pl.play(); else if (pl.canTogglePlaying) pl.togglePlaying(); }
                                }
                            }
                        }
                    }
                }
            }
        }
    }
}
