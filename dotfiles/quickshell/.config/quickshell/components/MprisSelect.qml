pragma Singleton

import QtQuick
import Quickshell.Services.Mpris

// Mpris 播放器选择：优先正在播放的，否则第一个。
// MusicInfo / MprisButton / MediaPlayer 共用，逻辑只留一份。
QtObject {
    function pick() {
        var ps = Mpris.players.values;
        for (var i = 0; i < ps.length; i++) {
            if (ps[i].isPlaying)
                return ps[i];
        }
        return ps.length > 0 ? ps[0] : null;
    }
}
