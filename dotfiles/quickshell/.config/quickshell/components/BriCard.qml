import QtQuick
import Quickshell.Io

// 亮度滑动卡：overlay 承载。打开/设置后刷新当前值；拖动只改本地预览，
// 松手才提交（外接 ddcutil 单次约半秒，不能跟手写）。
Item {
    id: root
    property var theme
    property bool isExternal: false
    property bool vertical: false
    signal requestClose

    // 横向 280×68（顶栏用）；竖向 64×240（竖条用）：图标上、竖滑杆中、百分比下。
    width: vertical ? 64 : 280
    height: vertical ? 240 : 68
    implicitWidth: width
    implicitHeight: height

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
            visible: !root.vertical
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
                id: hIcon
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
                id: hPct
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

        // 竖向：图标上、竖滑杆中、百分比下、关闭钮底（图标与百分比复用横向的文本）
        Text {
            id: vIcon
            visible: root.vertical
            anchors.top: parent.top
            anchors.topMargin: 12
            anchors.horizontalCenter: parent.horizontalCenter
            text: hIcon.text
            font.pixelSize: 18
            font.family: root.theme.fontFamily
            color: root.theme.fg
        }
        SliderBar {
            id: vSlider
            visible: root.vertical
            anchors.top: vIcon.bottom
            anchors.topMargin: 10
            anchors.bottom: vPct.top
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            width: 32
            vertical: true
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
            id: vPct
            visible: root.vertical
            anchors.bottom: vClose.top
            anchors.bottomMargin: 8
            anchors.horizontalCenter: parent.horizontalCenter
            text: hPct.text
            font.pixelSize: 13
            font.family: root.theme.fontFamily
            color: root.theme.fg
        }
        Text {
            id: vClose
            visible: root.vertical
            anchors.bottom: parent.bottom
            anchors.bottomMargin: 10
            anchors.horizontalCenter: parent.horizontalCenter
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
