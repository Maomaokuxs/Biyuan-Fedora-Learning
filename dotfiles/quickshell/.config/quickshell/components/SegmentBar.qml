import QtQuick

// 分段刻度条：20 段逐段点亮，点按/拖动设置；与 SliderBar 同接口，可直接替换。
// value01 为 0..1 受控值；拖动时 onMoved 实时回调，松手 onReleased 精确回调。
Item {
    id: root
    property real value01: 0
    property var theme

    signal moved(real ratio)
    signal released(real ratio)

    property int segments: 20
    property real segGap: 3

    implicitWidth: 120
    implicitHeight: 20

    Row {
        anchors.verticalCenter: parent.verticalCenter
        width: parent.width
        height: 14
        spacing: root.segGap
        Repeater {
            model: root.segments
            Rectangle {
                property bool lit: index < Math.ceil(Math.max(0, Math.min(1, root.value01)) * root.segments)
                width: (parent.width - (root.segments - 1) * root.segGap) / root.segments
                height: parent.height
                radius: 2
                color: lit ? root.theme.fg : root.theme.muted
                opacity: lit ? 1.0 : 0.35
                Behavior on opacity { NumberAnimation { duration: 120; easing.type: Easing.OutCubic } }
                Behavior on color { ColorAnimation { duration: 120 } }
            }
        }
    }
    MouseArea {
        anchors.fill: parent
        onPressed: root.moved(ratioOf(mouse))
        onPositionChanged: { if (pressed) root.moved(ratioOf(mouse)); }
        onReleased: root.released(ratioOf(mouse))
        function ratioOf(m) {
            return Math.max(0, Math.min(1, m.x / width));
        }
    }
}
