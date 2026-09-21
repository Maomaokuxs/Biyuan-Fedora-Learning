import QtQuick
import Quickshell.Services.Pipewire

// 音量滑动卡：overlay 承载。滑杆实时写 Pipewire，静音键切换。
Item {
    id: root
    property var theme
    signal requestClose

    width: 280
    height: 68
    implicitWidth: 280
    implicitHeight: 68

    property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
    property real vol: (sink && sink.ready && sink.audio) ? sink.audio.volume : 0
    property bool muted: sink && sink.ready && sink.audio ? sink.audio.muted : false

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
                        var s = root.sink;
                        if (s && s.ready && s.audio)
                            s.audio.muted = !s.audio.muted;
                    }
                }
            }

            SliderBar {
                id: slider
                anchors.verticalCenter: parent.verticalCenter
                width: parent.width - 24 - 48 - 20 - 20
                theme: root.theme
                value01: root.vol
                onMoved: ratio => {
                    var s = root.sink;
                    if (s && s.ready && s.audio) {
                        if (s.audio.muted)
                            s.audio.muted = false;
                        s.audio.volume = Math.max(0, Math.min(1, ratio));
                    }
                }
                onReleased: ratio => {
                    var s = root.sink;
                    if (s && s.ready && s.audio)
                        s.audio.volume = Math.max(0, Math.min(1, ratio));
                }
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
