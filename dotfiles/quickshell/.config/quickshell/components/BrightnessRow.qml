// BrightnessRow.qml — 亮度控制行（内接/外接二选一），自带状态轮询与提交。
// mode: "internal"（sysfs+logind，快）或 "external"（ddcutil，慢，松手提交）
import QtQuick
import Quickshell.Io

Rectangle {
    id: root
    property var theme
    property string mode: "internal"

    width: parent.width
    height: 56
    radius: 12
    color: Qt.alpha(theme.accent, 0.18)

    Row {
        anchors { fill: parent; margins: 12 }
        spacing: 10

        // 图标固定 24 宽容器，亮度等级变化时布局不抖
        Item {
            anchors.verticalCenter: parent.verticalCenter
            width: 24; height: 24
            Text {
                anchors.centerIn: parent
                text: state.pct < 34 ? "󰃞" : (state.pct < 67 ? "󰃟" : "󰃠")
                font.pixelSize: 17; font.family: root.theme.fontFamily; color: root.theme.fg
            }
        }
        SegmentBar {
            anchors.verticalCenter: parent.verticalCenter
            width: parent.width - 24 - 44 - 20 - 20
            theme: root.theme
            value01: state.pct / 100
            enabled: !state.busy
            onMoved: ratio => { state.pct = Math.round(ratio * 100); }
            onReleased: ratio => { state.pct = Math.round(ratio * 100); state.commit(state.pct); }
        }
        Text {
            anchors.verticalCenter: parent.verticalCenter
            width: 44
            text: state.pct + "%"
            font.pixelSize: 12; font.family: root.theme.fontFamily; color: root.theme.fg
            horizontalAlignment: Text.AlignRight
        }
    }

    // 状态后端：轮询 + 松手提交
    Item {
        id: state
        property int pct: 50
        property bool busy: false
        function refresh() { poller.running = true; }
        Component.onCompleted: state.refresh()
        Process {
            id: poller
            command: ["bash", "-c", Exec.scriptDir + (root.mode === "external" ? "/brightness-external.sh" : "/brightness.sh")]
            stdout: StdioCollector {
                onStreamFinished: {
                    try {
                        var j = JSON.parse(this.text);
                        var m = /([0-9]+)%/.exec(j.text || "");
                        if (m) state.pct = Math.max(0, Math.min(100, parseInt(m[1])));
                    } catch (e) {}
                }
            }
        }
        function commit(v) {
            state.busy = true;
            setter.command = ["bash", "-c", Exec.scriptDir + "/brightness-set.sh " + root.mode + " " + String(v)];
            setter.running = true;
        }
        Process {
            id: setter
            onExited: { state.busy = false; refreshTimer.restart(); }
        }
        Timer { id: refreshTimer; interval: 900; onTriggered: state.refresh() }
    }
}
