import QtQuick
import Quickshell.Io

// 音量滑动卡：overlay 承载。滑杆经 wpctl 读写，静音键切换。
// Quickshell Pipewire 服务在新版 pipewire 下 sink 永不 ready，原生绑定弃用。
Item {
    id: root
    property var theme
    signal requestClose

    width: 280
    height: 68
    implicitWidth: 280
    implicitHeight: 68

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
            anchors.fill: parent
            anchors.margins: 12
            spacing: 10

            Text {
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
    }
}
