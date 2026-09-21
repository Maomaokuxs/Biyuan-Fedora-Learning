import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire
import "../components" as Comp

// 原生整体电平表：替代 cava 频谱。
// bar 上显示 8 格火花线（历史峰值），中键经 UiState 开关 overlay 可视化浮窗。
// 左键 toggle-music / 右键 toggle-lyric，与原 CavaBar 一致。
Comp.Pill {
    id: root
    property var theme
    property string screenName: ""
    anchorKey: "vizAnchorX"
    anchorScreen: screenName
    normalBg: theme ? theme.mediaBg : "#a89a98"  // FALLBACK: theme 常在
    normalFg: theme ? theme.fg : "#6a442f"  // FALLBACK: theme 常在
    textSize: 14

    property var history: []

    function levelChar(v) {
        var bars = " ▁▂▃▄▅▆▇█";
        return bars.charAt(Math.max(0, Math.min(8, Math.round(v * 8))));
    }

    pillText: {
        if (root.history.length === 0)
            return "";
        var h = root.history.slice(-8);
        while (h.length < 8)
            h.unshift(0);
        var s = "";
        for (var i = 0; i < h.length; i++)
            s += root.levelChar(h[i]);
        return s;
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
            var h = root.history;
            h.push(v);
            if (h.length > 140)
                h.splice(0, h.length - 140);
            root.history = h;
        }
    }

    onLeftClicked: {
        Comp.Exec.sh("bash " + Comp.Exec.vendorDir + "/toggle-music.sh");
    }
    onRightClicked: {
        Comp.Exec.sh("bash " + Comp.Exec.vendorDir + "/toggle-lyric.sh");
    }
    onMiddleClicked: Comp.UiState.toggleViz(root.screenName)

}
