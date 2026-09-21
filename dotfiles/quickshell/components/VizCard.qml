import QtQuick
import Quickshell.Services.Pipewire

// 电平可视化卡：由 shell.qml 的 overlay PanelWindow 承载。
// 自带 PwNodePeakMonitor + 140 点历史，与 bar 上的火花线独立工作。
Item {
    id: root
    property var theme
    signal requestClose

    width: 400
    height: 200
    implicitWidth: 400
    implicitHeight: 200

    property var history: []

    PwNodePeakMonitor {
        node: Pipewire.ready ? Pipewire.defaultAudioSink : null
        enabled: node !== null
        onPeaksChanged: {
            var v = 0;
            for (var i = 0; i < peaks.length; i++)
                v = Math.max(v, peaks[i]);
            v = Math.max(0, Math.min(1, v));
            var h = root.history;
            h.push(v);
            if (h.length > 140)
                h.splice(0, h.length - 140);
            root.history = h;
            vizCanvas.requestPaint();
        }
    }

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1

        Text {
            anchors.top: parent.top
            anchors.left: parent.left
            anchors.margins: 12
            text: "电平"
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            font.bold: true
            color: root.theme.fg
        }
        Text {
            anchors.top: parent.top
            anchors.right: parent.right
            anchors.margins: 12
            text: "✕"
            font.pixelSize: 13
            color: root.theme.muted
            MouseArea {
                anchors.fill: parent
                anchors.margins: -6
                onClicked: root.requestClose()
            }
        }
        Canvas {
            id: vizCanvas
            anchors.fill: parent
            anchors.margins: 12
            anchors.topMargin: 36
            onPaint: {
                var ctx = getContext("2d");
                ctx.clearRect(0, 0, width, height);
                var h = root.history;
                var n = h.length;
                if (n === 0)
                    return;
                var maxN = 140;
                var bw = width / maxN;
                ctx.fillStyle = root.theme.accent;
                for (var i = 0; i < n; i++) {
                    var bh = Math.max(2, h[i] * height);
                    var x = width - (n - i) * bw;
                    ctx.fillRect(x, height - bh, Math.max(1, bw - 1), bh);
                }
                // 当前峰值线
                ctx.fillStyle = root.theme.fg;
                var cur = h[n - 1] * height;
                ctx.fillRect(0, height - cur - 1, width, 2);
            }
        }
    }
}
