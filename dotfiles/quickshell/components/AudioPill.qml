import QtQuick
import Quickshell.Io
import Quickshell.Services.Pipewire

// 原生音量模块：替代 scripts/audio.sh。
// 显示语义与 waybar pulseaudio 一致：muted → " Muted"，否则按 0/<60/≥60
// 切 //。左键滑动条卡片，右键 pavucontrol，中键静音切换，滚轮 ±5%。
Pill {
    id: root
    property var sink: Pipewire.ready ? Pipewire.defaultAudioSink : null
    property string screenName: ""
    anchorKey: "volAnchorX"
    anchorScreen: screenName

    pillText: {
        var s = root.sink;
        if (!s || !s.ready || !s.audio)
            return "";
        if (s.audio.muted)
            return Icons.volMute + " Muted";
        var v = Math.round(s.audio.volume * 100);
        var icon = v === 0 ? Icons.vol0 : v < 60 ? Icons.volLow : Icons.volHigh;
        return icon + " " + v + "%";
    }

    onLeftClicked: {
        UiState.toggleVol(root.screenName);
    }
    onRightClicked: {
        Exec.run(["pavucontrol"]);
    }
    onMiddleClicked: {
        var s = root.sink;
        if (s && s.ready && s.audio)
            s.audio.muted = !s.audio.muted;
    }
    onScrollUp: {
        var s = root.sink;
        if (s && s.ready && s.audio)
            s.audio.volume = Math.min(1.0, s.audio.volume + 0.05);
    }
    onScrollDown: {
        var s = root.sink;
        if (s && s.ready && s.audio)
            s.audio.volume = Math.max(0.0, s.audio.volume - 0.05);
    }
}
