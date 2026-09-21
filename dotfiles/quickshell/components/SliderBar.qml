import QtQuick

// 横向滑动条：给音量/亮度卡片用，与 MediaPlayer 进度条同风格。
// value01 为 0..1 受控值；拖动时 onMoved 实时回调，松手 onReleased 精确回调。
Item {
    id: root
    property real value01: 0
    property var theme

    signal moved(real ratio)
    signal released(real ratio)

    implicitWidth: 120
    implicitHeight: 20

    Rectangle {
        id: track
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 6
        radius: 3
        color: root.theme.muted
        opacity: 0.5
        Rectangle {
            width: parent.width * Math.max(0, Math.min(1, root.value01))
            height: parent.height
            radius: 3
            color: root.theme.fg
            Behavior on width { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
        Rectangle {
            x: parent.width * Math.max(0, Math.min(1, root.value01)) - 7
            anchors.verticalCenter: parent.verticalCenter
            width: 14; height: 14; radius: 7
            color: root.theme.fg
            Behavior on x { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
        }
    }
    MouseArea {
        anchors.fill: parent
        onPressed: root.moved(ratioOf(mouse))
        onPositionChanged: { if (pressed) root.moved(ratioOf(mouse)); }
        onReleased: root.released(ratioOf(mouse))
        function ratioOf(m) {
            return Math.max(0, Math.min(1, m.x / track.width));
        }
    }
}
