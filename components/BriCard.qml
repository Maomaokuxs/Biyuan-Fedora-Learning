import QtQuick
import Quickshell.Io

// 亮度滑动卡：overlay 承载。打开/设置后刷新当前值；拖动只改本地预览，
// 松手才提交（外接 ddcutil 单次约半秒，不能跟手写）。
Item {
    id: root
    property var theme
    property bool isExternal: false
    signal requestClose

    width: 280
    height: 68
    implicitWidth: 280
    implicitHeight: 68

    property int pct: 50
    property bool busy: false

    function refresh() {
        poller.running = true;
    }
    onVisibleChanged: { if (visible) root.refresh(); }
    Component.onCompleted: root.refresh()

    Process {
        id: poller
        // 经 bash -c 中转，~ 由 shell 展开（command 数组直传不展开）
        command: ["bash", "-c", root.isExternal
            ? Exec.scriptDir + "/brightness-external.sh"
            : Exec.scriptDir + "/brightness.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text);
                    var m = /([0-9]+)%/.exec(j.text || "");
                    if (m)
                        root.pct = Math.max(0, Math.min(100, parseInt(m[1])));
                } catch (e) {}
            }
        }
    }

    function commit(v) {
        root.busy = true;
        setter.command = ["bash", "-c",
            Exec.scriptDir + "/brightness-set.sh "
            + (root.isExternal ? "external " : "internal ") + String(v)];
        setter.running = true;
    }
    Process {
        id: setter
        onExited: {
            root.busy = false;
            // ddc 写入慢半拍，延迟重读一次对齐显示
            refreshTimer.restart();
        }
    }
    Timer {
        id: refreshTimer
        interval: 900
        onTriggered: root.refresh()
    }

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
        clip: true

        Row {
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "󰃟"
                font.pixelSize: 18
                font.family: root.theme.fontFamily
                color: root.theme.fg
            }

            SliderBar {
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24 - 48 - 20 - 20
                theme: root.theme
                value01: root.pct / 100
                enabled: !root.busy
                onMoved: ratio => {
                    root.pct = Math.round(ratio * 100);
                }
                onReleased: ratio => {
                    root.pct = Math.round(ratio * 100);
                    root.commit(root.pct);
                }
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                text: root.pct + "%"
                font.pixelSize: 13
                font.family: root.theme.fontFamily
                color: root.theme.fg
                horizontalAlignment: Text.AlignRight
            }

            Text {
                anchors.verticalCenter: parent.verticalCenter
                text: "✕"
                font.pixelSize: 12
                color: root.theme.muted
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: root.requestClose()
                }
            }
        }
    }
}
