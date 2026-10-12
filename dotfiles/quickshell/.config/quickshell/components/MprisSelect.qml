pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

// Mpris 播放器选择：优先正在播放的，否则第一个。
// MusicInfo / MprisButton / MediaPlayer 共用，逻辑只留一份。
// valid 守卫：跳过已退出的僵尸对象，否则歌名/按钮会卡在最后一首。
QtObject {
    // 上次在播的播放器 dbus 名：暂停后优先粘住它，不乱跳到 chromium 这类
    property string lastPlaying: ""
    function pick() {
        var ps = Mpris.players.values;
        var fallback = null;
        var sticky = null;
        for (var i = 0; i < ps.length; i++) {
            try {
                if (ps[i].valid === false)
                    continue;
                if (ps[i].isPlaying) {
                    try { lastPlaying = ps[i].dbusName || ""; } catch (e2) {}
                    return ps[i];
                }
                if (!fallback)
                    fallback = ps[i];
                try {
                    if (lastPlaying !== "" && ps[i].dbusName === lastPlaying)
                        sticky = ps[i];
                } catch (e3) {}
            } catch (e) {}
        }
        return sticky || fallback;
    }
}
