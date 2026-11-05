import QtQuick
import QtQuick.Layouts
import Quickshell.Services.Mpris

// 胶囊式歌曲模块（2026-10-10）：32px 高 pill，内置 24px 圆形封面、
// 歌名（12 字截断）、上一曲/播放/下一曲，播放进度环绕播放键。
// 暂停不隐藏，只有播放器退出才收起。
Rectangle {
    id: root
    property string screenName: ""
    property var theme
    property string normalBg: "#998c8c"
    property string normalFg: "#6a442f"
    property var player: MprisSelect.pick()
    signal leftClicked
    signal middleClicked
    signal rightClicked

    // 播放进度
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
        interval: 1000
        running: root.visible && root.player && root.player.isPlaying
        repeat: true
        onTriggered: {
            root.pos += 1;
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
    Component.onCompleted: {
        root.shown = root.hasPlayer;
        root.syncPos();
        updateAnchor();
    }

    // 显隐：只看播放器在不在（暂停也显示），播放器退出 500ms 后才收起
    property bool hasPlayer: !!root.player
    property bool shown: true
    Timer {
        id: hideDebounce
        interval: 500
        onTriggered: { if (!root.hasPlayer) root.shown = false; }
    }
    onHasPlayerChanged: {
        if (root.hasPlayer) {
            hideDebounce.stop();
            root.shown = true;
        } else {
            hideDebounce.restart();
        }
    }
    // 竖条模式：缩成封面+播放方块（横向的歌名/上下曲/进度环全部收起，
    // 簇内其余两件由 Bar 在竖条时隐藏；竖贴是独立 Column，不动横向 Row）
    // 歌名单行显示在播放键下方，过长截断（elide），高跟内容走。
    property bool vertical: false
    property real fixedWidth: 190
    property real contentW: vertical ? UiState.tileW : (fixedWidth > 0 ? fixedWidth : row.implicitWidth + 20)
    property real contentH: vertical ? vCol.implicitHeight + 6 : 32
    property string trackTitle: (root.player && root.player.trackTitle) || ""
    property real animW: shown ? contentW : 0
    property real animH: shown ? contentH : 0
    Behavior on animW { enabled: UiState.animReady; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on animH { enabled: UiState.animReady; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on opacity { enabled: UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }
    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    height: vertical ? contentH : 32
    width: contentW
    Layout.preferredWidth: animW
    Layout.preferredHeight: vertical ? animH : 32
    radius: 10
    clip: true
    color: mouse.containsMouse ? normalFg : normalBg
    Behavior on color { ColorAnimation { duration: 200 } }

    // 锚点上报（给 popup 定位用）
    property string anchorKey: "music"
    function updateAnchor() {
        if (anchorKey !== "" && root.screenName !== "")
            UiState.anchorMap[anchorKey + "_" + root.screenName] = 0;
    }
    onWidthChanged: updateAnchor()
    Timer { interval: 1000; running: anchorKey !== ""; repeat: true; onTriggered: updateAnchor() }

    Row {
        id: row
        visible: !root.vertical
        anchors.left: parent.left
        anchors.leftMargin: 4
        anchors.verticalCenter: parent.verticalCenter
            spacing: 8

            // 封面
            Rectangle {
                width: 24; height: 24
                radius: 7
                color: "transparent"
                clip: true
                anchors.verticalCenter: parent.verticalCenter
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
                    text: "♪"
                    font.pixelSize: 12
                    color: mouse.containsMouse ? root.normalBg : root.normalFg
                    visible: !root.player || !root.player.trackArtUrl
                }
            }

            // 歌名（定宽，按钮不随歌名长度位移）
            Text {
                id: label
                width: 70
                anchors.verticalCenter: parent.verticalCenter
                text: {
                    var p = root.player;
                    if (!p) return "";
                    var t = p.trackTitle || "";
                    return t.length <= 12 ? t : t.slice(0, 9) + "...";
                }
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                color: mouse.containsMouse ? root.normalBg : root.normalFg
                Behavior on color { ColorAnimation { duration: 200 } }
                elide: Text.ElideRight
            }

            // 上一曲
            Text {
                id: prevBtn
                z: 2
                property bool hovered: false
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.prev
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                font.bold: true
                color: mouse.containsMouse ? root.normalBg : root.normalFg
                opacity: (root.player && root.player.canGoPrevious) ? (hovered ? 1 : 0.85) : 0.3
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited: parent.hovered = false
                    onClicked: {
                        if (root.player && root.player.canGoPrevious)
                            root.player.previous();
                        mouse.accepted = true;
                    }
                }
            }

            // 播放/暂停（含进度环）
            Item {
                id: playWrap
                z: 2
                width: 30; height: 30
                anchors.verticalCenter: parent.verticalCenter
                property bool hovered: false
                // 进度环
                Canvas {
                    id: ring
                    anchors.centerIn: parent
                    width: 28; height: 28
                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.clearRect(0, 0, width, height);
                        ctx.strokeStyle = Qt.alpha(mouse.containsMouse ? root.normalBg : root.normalFg, 0.25);
                        ctx.lineWidth = 1.5;
                        ctx.beginPath();
                        ctx.arc(14, 14, 12.8, 0, Math.PI * 2);
                        ctx.stroke();
                        if (root.ratio > 0) {
                            ctx.strokeStyle = mouse.containsMouse ? root.normalBg : root.normalFg;
                            ctx.beginPath();
                            ctx.arc(14, 14, 12.8, -Math.PI / 2, -Math.PI / 2 + Math.PI * 2 * root.ratio);
                            ctx.stroke();
                        }
                    }
                    Connections {
                        target: root
                        function onRatioChanged() { ring.requestPaint(); }
                        function onNormalFgChanged() { ring.requestPaint(); }
                        function onNormalBgChanged() { ring.requestPaint(); }
                    }
                }
                Rectangle {
                    anchors.centerIn: parent
                    width: 24; height: 24
                    radius: 12
                    color: mouse.containsMouse ? root.normalBg : root.normalFg
                    opacity: playWrap.hovered ? 0.9 : 1
                    Behavior on color { ColorAnimation { duration: 150 } }
                }
                Text {
                    width: 24; height: 24
                    anchors.centerIn: parent
                    text: (root.player && root.player.isPlaying) ? Icons.pause : Icons.play
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                    font.bold: true
                    leftPadding: 1
                    color: mouse.containsMouse ? root.normalFg : root.normalBg
                    horizontalAlignment: Text.AlignHCenter
                    verticalAlignment: Text.AlignVCenter
                }
                MouseArea {
                    anchors.fill: parent
                    hoverEnabled: true
                    onEntered: playWrap.hovered = true
                    onExited: playWrap.hovered = false
                    onClicked: {
                        var pl = root.player;
                        if (!pl) return;
                        if (pl.isPlaying) {
                            if (pl.canTogglePlaying) pl.togglePlaying();
                            else if (pl.canPause) pl.pause();
                        } else {
                            if (pl.canPlay) pl.play();
                            else if (pl.canTogglePlaying) pl.togglePlaying();
                        }
                        mouse.accepted = true;
                    }
                }
            }

            // 下一曲
            Text {
                id: nextBtn
                z: 2
                property bool hovered: false
                anchors.verticalCenter: parent.verticalCenter
                text: Icons.next
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 13
                font.bold: true
                color: mouse.containsMouse ? root.normalBg : root.normalFg
                opacity: (root.player && root.player.canGoNext) ? (hovered ? 1 : 0.85) : 0.3
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    hoverEnabled: true
                    onEntered: parent.hovered = true
                    onExited: parent.hovered = false
                    onClicked: {
                        if (root.player && root.player.canGoNext)
                            root.player.next();
                        mouse.accepted = true;
                    }
                }
            }
        }

    // 竖贴：封面在上、播放键在下（与横向播放键同逻辑，独立一套控件，
    // 不与横向 Row 抢子项；上下曲/进度环竖条时不画，歌名样式 B 拆两行）
    Column {
        id: vCol
        anchors.centerIn: parent
        spacing: 3
        visible: root.vertical
        Rectangle {
            width: 24; height: 24
            radius: 7
            color: "transparent"
            clip: true
            anchors.horizontalCenter: parent.horizontalCenter
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
                text: "♪"
                font.pixelSize: 14
                color: mouse.containsMouse ? root.normalBg : root.normalFg
                visible: !root.player || !root.player.trackArtUrl
            }
        }
        Item {
            id: vPlayWrap
            width: 24; height: 24
            anchors.horizontalCenter: parent.horizontalCenter
            property bool hovered: false
            Rectangle {
                anchors.centerIn: parent
                width: 24; height: 24
                radius: 12
                color: mouse.containsMouse ? root.normalBg : root.normalFg
                opacity: vPlayWrap.hovered ? 0.9 : 1
            }
            Text {
                anchors.centerIn: parent
                text: (root.player && root.player.isPlaying) ? Icons.pause : Icons.play
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 14
                font.bold: true
                color: mouse.containsMouse ? root.normalFg : root.normalBg
                horizontalAlignment: Text.AlignHCenter
                verticalAlignment: Text.AlignVCenter
            }
            MouseArea {
                anchors.fill: parent
                hoverEnabled: true
                onEntered: vPlayWrap.hovered = true
                onExited: vPlayWrap.hovered = false
                onClicked: {
                    var pl = root.player;
                    if (!pl) return;
                    if (pl.isPlaying) {
                        if (pl.canTogglePlaying) pl.togglePlaying();
                        else if (pl.canPause) pl.pause();
                    } else {
                        if (pl.canPlay) pl.play();
                        else if (pl.canTogglePlaying) pl.togglePlaying();
                    }
                    mouse.accepted = true;
                }
            }
        }
        // 歌名单行：无歌名时隐藏、不占位；过长截断
        Text {
            visible: root.trackTitle !== ""
            width: UiState.tileW - 2
            anchors.horizontalCenter: parent.horizontalCenter
            text: root.trackTitle
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 10
            color: mouse.containsMouse ? root.normalBg : root.normalFg
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        z: -1
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        onClicked: mouseEvent => {
            // 播放键已处理自己的点击，这里只处理空白区
            if (mouseEvent.button === Qt.LeftButton) {
                root.leftClicked();
                // 左键仅发信号，不弹框
            } else if (mouseEvent.button === Qt.RightButton) {
                root.rightClicked();
            } else if (mouseEvent.button === Qt.MiddleButton) {
                root.middleClicked();
            }
        }
    }

    // 播放器消失则收卡；加 2s 宽限
    Timer {
        id: nullGrace
        interval: 2000
        onTriggered: { if (!root.player) UiState.mediaOpen = false; }
    }
    onPlayerChanged: {
        if (!root.player) nullGrace.restart();
        else nullGrace.stop();
    }
}