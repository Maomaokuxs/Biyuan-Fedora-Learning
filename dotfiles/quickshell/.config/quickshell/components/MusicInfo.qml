import QtQuick
import Quickshell.Services.Mpris

// 原生 music 模块：替代 music.py 轮询。
// 文本语义与 music.py 一致：无播放器/无标题 → 隐藏；playing  否则 ；
// 超过 18 字符截断为 15 + "..."。左键经 UiState 开关 overlay 播放卡，
// 中键 play-pause，右键 next，滚轮 ±5% 音量。
Pill {
    id: root
    property bool musicHidden: false
    property var theme
    property string screenName: ""
    anchorKey: "mediaAnchorX"
    anchorScreen: screenName

    property var player: MprisSelect.pick()

    pillText: {
        if (root.musicHidden)
            return "";
        var p = root.player;
        if (!p)
            return "";
        var t = p.trackTitle || "";
        if (t === "")
            return "";
        var a = p.trackArtist || "";
        var full = a !== "" ? t + " - " + a : t;
        var disp = full.length <= 18 ? full : full.slice(0, 15) + "...";
        return (p.isPlaying ? Icons.musicPlaying + " " : Icons.musicPaused + " ") + disp;
    }

    onLeftClicked: {
        if (root.player)
            UiState.toggleMedia(root.screenName);
    }
    onMiddleClicked: {
        if (root.player && root.player.canTogglePlaying)
            root.player.togglePlaying();
    }
    onRightClicked: {
        if (root.player && root.player.canGoNext)
            root.player.next();
    }
    onScrollUp: {
        var p = root.player;
        if (p && p.volumeSupported)
            p.volume = Math.min(1.0, p.volume + 0.05);
    }
    onScrollDown: {
        var p = root.player;
        if (p && p.volumeSupported)
            p.volume = Math.max(0.0, p.volume - 0.05);
    }

    // 播放器消失则收卡；加 2s 宽限，Mpris 瞬断重建时不误关
    Timer {
        id: nullGrace
        interval: 2000
        onTriggered: {
            if (!root.player)
                UiState.mediaOpen = false;
        }
    }
    onPlayerChanged: {
        if (!root.player)
            nullGrace.restart();
        else
            nullGrace.stop();
    }
}
