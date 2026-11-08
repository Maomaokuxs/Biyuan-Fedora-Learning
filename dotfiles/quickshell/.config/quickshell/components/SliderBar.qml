import QtQuick

// 滑动条：给音量/亮度卡片用，与 MediaPlayer 进度条同风格。
// value01 为 0..1 受控值；拖动时 onMoved 实时回调，松手 onReleased 精确回调。
// 横向（默认）：左→右 0→1；竖向（vertical: true）：下→上 0→1。
Item {
    id: root
    property real value01: 0
    property var theme
    property bool vertical: false

    signal moved(real ratio)
    signal released(real ratio)

    implicitWidth: vertical ? 32 : 120
    implicitHeight: vertical ? 120 : 20

    Rectangle {
        id: track
        anchors.centerIn: parent
        width: root.vertical ? 16 : parent.width
        height: root.vertical ? parent.height - 24 : 6
        radius: root.vertical ? 8 : 3
        color: root.theme.muted
        opacity: 0.5
        Rectangle {
            anchors.left: root.vertical ? undefined : parent.left
            anchors.bottom: root.vertical ? parent.bottom : undefined
            width: root.vertical ? parent.width : parent.width * Math.max(0, Math.min(1, root.value01))
            height: root.vertical ? parent.height * Math.max(0, Math.min(1, root.value01)) : parent.height
            radius: root.vertical ? 8 : 3
            color: root.theme.fg
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on height { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            x: root.vertical ? (parent.width - 24) / 2 : parent.width * Math.max(0, Math.min(1, root.value01)) - 7
            y: root.vertical ? parent.height * (1 - Math.max(0, Math.min(1, root.value01))) - 12 : (parent.height - 14) / 2
            width: root.vertical ? 24 : 14; height: root.vertical ? 24 : 14; radius: root.vertical ? 12 : 7
            color: root.theme.fg
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
            Behavior on y { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        onPressed: root.moved(ratioOf(mouse))
        onPositionChanged: { if (pressed) root.moved(ratioOf(mouse)); }
        onReleased: root.released(ratioOf(mouse))
        function ratioOf(m) {
            if (root.vertical)
                return Math.max(0, Math.min(1, 1 - (m.y - 12) / Math.max(1, track.height)));
            return Math.max(0, Math.min(1, m.x / track.width));
        }
    }
}
