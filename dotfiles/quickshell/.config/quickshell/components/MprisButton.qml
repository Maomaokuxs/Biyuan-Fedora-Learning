import QtQuick
import Quickshell.Services.Mpris

// 原生 mpris 传输键：替代 mprev/mplay/mnext 三个 ScriptPill。
// mode: "prev" | "toggle" | "next"，图标与 waybar exec 一致。
Pill {
    id: root
    property string mode: "toggle"
    property bool musicHidden: false

    property var player: MprisSelect.pick()

    pillText: {
        if (root.musicHidden || !root.player)
            return "";
        if (root.mode === "prev")
            return Icons.prev;
        if (root.mode === "next")
            return Icons.next;
        return root.player.isPlaying ? Icons.pause : Icons.play;
    }

    onLeftClicked: {
        var p = root.player;
        if (!p)
            return;
        if (root.mode === "prev") {
            if (p.canGoPrevious)
                p.previous();
        } else if (root.mode === "next") {
            if (p.canGoNext)
                p.next();
        } else {
            if (p.canTogglePlaying)
                p.togglePlaying();
        }
    }
}
