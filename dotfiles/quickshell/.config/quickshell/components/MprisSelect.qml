pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

// Mpris 播放器选择：优先正在播放的，否则第一个。
// MusicInfo / MprisButton / MediaPlayer 共用，逻辑只留一份。
// valid 守卫：跳过已退出的僵尸对象，否则歌名/按钮会卡在最后一首。
QtObject {
    function pick() {
        var ps = Mpris.players.values;
        var fallback = null;
        for (var i = 0; i < ps.length; i++) {
            try {
                if (ps[i].valid === false)
                    continue;
                if (ps[i].isPlaying)
                    return ps[i];
                if (!fallback)
                    fallback = ps[i];
            } catch (e) {}
        }
        return fallback;
    }
}
