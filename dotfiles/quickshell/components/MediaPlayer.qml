import QtQuick
import Quickshell.Services.Mpris

// 安卓风格播放卡·透明版：无背景色，直接衬在壁纸上（配色由 hellwal 保证对比），
// 风格对齐顶栏 pill。布局保证塞进 360x132：封面 96 + 右列（标题/艺人/进度/三键）。
Item {
    id: root
    property var theme
    signal requestClose

    property var player: MprisSelect.pick()

    width: 360
    height: 132
    implicitWidth: 360
    implicitHeight: 132

    // 本地进度：播放时 Timer 累加，拖动时直写 player.position。
    // len 用直接绑定：Mpris 各属性异步分批到达，信号易错过，绑定由引擎跟踪。
    property double pos: 0
    property double len: {
        var p = root.player;
        if (!p)
            return 0;
        if (p.lengthSupported && p.length > 0)
            return p.length;
        if (p.metadata) {
            var ml = p.metadata["mpris:length"];
            if (ml > 0)
                return ml / 1000000;
        }
        return 0;
    }

    function fmt(s) {
        s = Math.max(0, Math.floor(s || 0));
        return Math.floor(s / 60) + ":" + String(s % 60).padStart(2, "0");
    }
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
            if (root.len > 0 && root.pos > root.len)
                root.pos = root.len;
        }
    }
    Connections {
        target: root.player
        function onTrackTitleChanged() { root.syncPos(); }
        function onPositionChanged() {
            // 外部 seek（非本卡拖动）时跟随；新歌从头播差异大也会自动纠正
            if (root.player && Math.abs(root.player.position - root.pos) > 1.5)
                root.pos = root.player.position;
        }
    }
    Component.onCompleted: root.syncPos()

    // 底色与壁纸选择器一致：theme.bg 实底 + muted 细边，内容收进裁剪
    Rectangle {
        anchors.fill: parent
        radius: 20
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
        clip: true

        // ✕ 悬浮右上（标题行给它留 20px）
        Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 6
            text: "✕"
            font.pixelSize: 12
            color: root.theme.muted
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: root.requestClose()
            }
        }

    Row {
        anchors.fill: parent
        anchors.margins: 12
        spacing: 8

        // 封面
        Rectangle {
            width: 96; height: 96
            anchors.verticalCenter: parent.verticalCenter
            radius: 14
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
                color: root.theme.fg
                visible: !root.player || !root.player.trackArtUrl
            }
        }

        // 右列：标题/艺人/进度/三键，总高 20+13+22+34+3*3=98 ≤ 108
        Column {
            width: parent.width - 96 - 8
            anchors.verticalCenter: parent.verticalCenter
            spacing: 3

            Text {
                width: parent.width - 20
                text: (root.player && root.player.trackTitle) || "无标题"
                font.family: root.theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                color: root.theme.fg
                elide: Text.ElideRight
                maximumLineCount: 1
            }
            Text {
                width: parent.width - 20
                text: (root.player && root.player.trackArtist) || ""
                font.family: root.theme.fontFamily
                font.pixelSize: 12
                color: root.theme.muted
                elide: Text.ElideRight
                maximumLineCount: 1
                visible: text !== ""
            }

            // 进度条
            Item {
                width: parent.width
                height: 20
                property double ratio: root.len > 0 ? Math.min(1, root.pos / root.len) : 0
                Text {
                    id: curT
                    anchors.left: parent.left
                    anchors.top: parent.top
                    text: root.fmt(root.pos)
                    font.pixelSize: 10
                    color: root.theme.muted
                    font.family: root.theme.fontFamily
                }
                Text {
                    id: totT
                    anchors.right: parent.right
                    anchors.top: parent.top
                    text: root.fmt(root.len)
                    font.pixelSize: 10
                    color: root.theme.muted
                    font.family: root.theme.fontFamily
                }
                Rectangle {
                    id: track
                    anchors.bottom: parent.bottom
                    width: parent.width
                    height: 5
                    radius: 2.5
                    color: root.theme.muted
                    opacity: 0.5
                    Rectangle {
                        width: parent.width * parent.parent.ratio
                        height: parent.height
                        radius: 2.5
                        color: root.theme.fg
                        Behavior on width { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
                    Rectangle {
                        x: parent.width * parent.parent.ratio - 5
                        anchors.verticalCenter: parent.verticalCenter
                        width: 10; height: 10; radius: 5
                        color: root.theme.fg
                        Behavior on x { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
                    }
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
                        if (root.player)
                            root.player.position = t;
                    }
                }
            }

            // 控制行：上曲/播放/下曲三键均分
                // 控制组：以进度条中点为中心聚拢，三个高亮圆等距排布
                // 控制组：三键同尺寸圆（36），等分铺满，以进度条中点为中心
                Row {
                    width: parent.width
                    Item {
                        property bool hovered: false
                        width: parent.width / 3; height: 40
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22; height: 22; radius: 11
                            color: parent.hovered ? Qt.lighter(root.theme.accent, 1.12) : root.theme.accent
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: Icons.prev
                            font.pixelSize: 12
                            font.family: root.theme.fontFamily
                            color: root.theme.fg
                            opacity: (root.player && root.player.canGoPrevious) ? 1 : 0.3
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: { if (root.player && root.player.canGoPrevious) root.player.previous(); }
                        }
                    }
                    Item {
                        property bool hovered: false
                        width: parent.width / 3; height: 40
                        Rectangle {
                            anchors.centerIn: parent
                            width: 36; height: 36; radius: 18
                            color: parent.hovered ? Qt.lighter(root.theme.accent, 1.12) : root.theme.accent
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: (root.player && root.player.isPlaying) ? Icons.pause : Icons.play
                            font.pixelSize: 16
                            font.family: root.theme.fontFamily
                            color: root.theme.fg
                            opacity: 1
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: { if (root.player && root.player.canTogglePlaying) root.player.togglePlaying(); }
                        }
                    }
                    Item {
                        property bool hovered: false
                        width: parent.width / 3; height: 40
                        Rectangle {
                            anchors.centerIn: parent
                            width: 22; height: 22; radius: 11
                            color: parent.hovered ? Qt.lighter(root.theme.accent, 1.12) : root.theme.accent
                            Behavior on color { ColorAnimation { duration: 120 } }
                        }
                        Text {
                            anchors.centerIn: parent
                            text: Icons.next
                            font.pixelSize: 12
                            font.family: root.theme.fontFamily
                            color: root.theme.fg
                            opacity: (root.player && root.player.canGoNext) ? 1 : 0.3
                        }
                        MouseArea {
                            anchors.fill: parent
                            hoverEnabled: true
                            onEntered: parent.hovered = true
                            onExited: parent.hovered = false
                            onClicked: { if (root.player && root.player.canGoNext) root.player.next(); }
                        }
                    }
                }
                }
        }
    }
    }
