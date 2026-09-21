import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../components" as Comp

// 真频谱柱 + 峰值回落：spectrum.py 在就吃真分频，
// 缺失/起不来时回落为单峰值齐涨（至少会动，静默时基线）。
// Canvas 圆头线条上下镜像绘制，无声时剩一条虚线基线。
// 背景固定（hover 不换色，保证画笔始终可见）。
// 左键 toggle-music / 右键 toggle-lyric，与原 CavaBar 一致。
Comp.Pill {
    id: root
    property var theme
    property string screenName: ""
    anchorKey: "vizAnchorX"
    anchorScreen: screenName
    // 背景恒定，hover 不反色（画布墨水才始终可见）
    normalBg: theme ? theme.mediaBg : "#a89a98"  // FALLBACK: theme 常在
    normalFg: theme ? theme.mediaBg : "#a89a98"
    fixedWidth: 104
    pillText: " "

    property int bars: 12
    property var levels: []
    // 单路平滑态（频谱缺席时的回落源）
    property real smoothSig: 0
    // 绑定即实例化单例（单例懒加载，不绑就永远不启动频谱进程）
    property bool fftOn: Comp.SpectrumState.fftOk

    onLevelsChanged: vizCanvas.requestPaint()

    Canvas {
        id: vizCanvas
        anchors.fill: parent
        anchors.leftMargin: 8
        anchors.rightMargin: 8
        anchors.topMargin: 2
        anchors.bottomMargin: 2
        antialiasing: true
        renderStrategy: Canvas.Threaded
        onPaint: {
            var ctx = getContext("2d");
            var w = width, h = height;
            ctx.clearRect(0, 0, w, h);
            ctx.lineWidth = 3.5;
            ctx.lineCap = "round";
            ctx.strokeStyle = root.theme ? root.theme.fg : "#6a442f";
            var n = root.levels.length > 0 ? root.levels.length : root.bars;
            // 中间对称、上下齐长：起点是中线
            var cy = h / 2, maxR = h / 2 - 2;
            for (var i = 0; i < n; i++) {
                var v = root.levels.length > i ? root.levels[i] : 0;
                var len = Math.max(1.5, v * maxR);
                var x = n > 1 ? (i / (n - 1)) * (w - 4) + 2 : w / 2;
                ctx.beginPath();
                ctx.moveTo(x, cy - len);
                ctx.lineTo(x, cy + len);
                ctx.stroke();
            }
        }
    }
    // 静默时也定时重绘，保证换肤后颜色跟上
    Timer {
        interval: 2000
        running: true
        repeat: true
        onTriggered: vizCanvas.requestPaint()
    }

    PwNodePeakMonitor {
        id: monitor
        node: Pipewire.ready ? Pipewire.defaultAudioSink : null
        enabled: node !== null
        onPeaksChanged: {
            var v = 0;
            for (var i = 0; i < peaks.length; i++)
                v = Math.max(v, peaks[i]);
            v = Math.max(0, Math.min(1, v));
            // 单路平滑：只给频谱缺席回落用
            var sig = root.smoothSig + (v - root.smoothSig) * (v > root.smoothSig ? 0.6 : 0.15);
            root.smoothSig = sig;
            // 频谱在：真分频按对子平均后镜像，两端严格对称；再做一层平滑，
            // 直播帧率太快直接显示会晃眼；不在：单峰值齐涨保底
            var live = Comp.SpectrumState.bands;
            if (live.length >= 12) {
                var half = [];
                for (var j = 0; j < 6; j++)
                    half.push((live[j] + live[11 - j]) / 2);
                var target = half.concat(half.slice().reverse()).slice(0, root.bars);
                var cur2 = root.levels;
                if (cur2.length !== root.bars)
                    cur2 = [];
                var next2 = [];
                for (var i = 0; i < root.bars; i++) {
                    var old2 = cur2.length > i ? cur2[i] : 0;
                    var k2 = target[i] > old2 ? 0.45 : 0.12;
                    next2.push(old2 + (target[i] - old2) * k2);
                }
                root.levels = next2;
            } else {
                var next = [];
                for (var i = 0; i < root.bars; i++)
                    next.push(sig);
                root.levels = next;
            }
        }
    }

    onLeftClicked: {
        Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music.sh");
    }
    onRightClicked: {
        Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-lyric.sh");
    }
    onMiddleClicked: Comp.UiState.toggleViz(root.screenName)

}
