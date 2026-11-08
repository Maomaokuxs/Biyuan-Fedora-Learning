import QtQuick
import Quickshell.Io

// 音量滑动卡：overlay 承载。滑杆经 wpctl 读写，静音键切换。
// Quickshell Pipewire 服务在新版 pipewire 下 sink 永不 ready，原生绑定弃用。
Item {
    id: root
    property var theme
    property bool vertical: false
    signal requestClose

    // 横向 280×68（顶栏用）；竖向 64×240（竖条用）：图标上、竖滑杆中、百分比下。
    width: vertical ? 64 : 280
    height: vertical ? 240 : 68
    implicitWidth: width
    implicitHeight: height

    property real vol: 0
    property bool muted: false

    function refresh() { poller.running = true; }
    Component.onCompleted: root.refresh()

    Timer {
        id: ticker
        interval: 1000
        repeat: true
        running: true
        onTriggered: { if (!poller.running) poller.running = true; }
    }

    Process {
        id: poller
        command: ["bash", "-c", Exec.commonDir + "/audio.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var j = JSON.parse(this.text);
                    root.vol = Math.max(0, Math.min(1, Number(j.vol || 0)));
                    root.muted = !!j.muted;
                } catch (e) {}
            }
        }
    }

    function setVol(ratio, commit) {
        var v = Math.max(0, Math.min(1, ratio));
        if (commit)
            Exec.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", v.toFixed(2)]);
        else
            Exec.run(["bash", "-c", "wpctl set-mute @DEFAULT_AUDIO_SINK@ 0 >/dev/null; wpctl set-volume @DEFAULT_AUDIO_SINK@ " + v.toFixed(2)]);
        root.refresh();
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
                text: root.muted ? "󰝟" : (root.vol <= 0 ? "" : root.vol < 0.6 ? "" : "")
                font.pixelSize: 18
                font.family: root.theme.fontFamily
                color: root.theme.fg
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -6
                    onClicked: {
                        Exec.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                        root.refresh();
                    }
                }
            }

            SliderBar {
                id: slider
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24 - 48 - 20 - 20
                theme: root.theme
                value01: root.vol
                onMoved: ratio => root.setVol(ratio, false)
                onReleased: ratio => root.setVol(ratio, true)
            }

            Text {
                id: hPct
                anchors.verticalCenter: parent.verticalCenter
                width: 48
                text: root.muted ? "静音" : Math.round(root.vol * 100) + "%"
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
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: {
                    Exec.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
                    root.refresh();
                }
            }
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
            value01: root.vol
            onMoved: ratio => root.setVol(ratio, false)
            onReleased: ratio => root.setVol(ratio, true)
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
