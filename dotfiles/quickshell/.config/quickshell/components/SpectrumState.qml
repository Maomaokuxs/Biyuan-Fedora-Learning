pragma Singleton

import QtQuick
import Quickshell.Io
import Quickshell.Services.Mpris

// 声谱服务：单例跑 spectrum.py（pw-record 直采 + numpy rfft），双屏共用一份。
// 全浮点行协议 "0.312;0.045;…"（12 柱，0-1.5），直存 bands，量化只在落像素时发生。
// 按需启停：切到声谱且有播放器在播才跑进程，否则停进程清数据，静默零开销。
// 起不来时 bands 常空，调用方自行回落。
Item {
    id: root
    visible: false

    property var bands: []
    // 任一播放器在播：播放开关的唯一事实源（舞者/频谱/暂停压平共用）。
    // valid 守卫：播放器退出后模型里可能留僵尸对象，valid===false 的直接跳过
    // （无该属性时 undefined !== false，不影响旧逻辑）
    property bool anyPlaying: {
        var vs = Mpris.players.values;
        for (var i = 0; i < vs.length; i++) {
            try {
                if (vs[i].valid !== false && vs[i].isPlaying)
                    return true;
            } catch (e) {}
        }
        return false;
    }
    // 有没有播放器（暂停也算有）：模块显隐的门；暂停留 baseline，只有人走茶凉才藏
    property bool hasPlayer: {
        var vs = Mpris.players.values;
        for (var i = 0; i < vs.length; i++) {
            try {
                if (vs[i].valid !== false)
                    return true;
            } catch (e) {}
        }
        return false;
    }
    // 任一播放器在播 + 切到声谱 + 总闸没拉下才需要进程（尾闸只藏跟随者，不管本模块）
    property bool wantSpectrum: UiState.vizEffect === "spectrum" && root.anyPlaying && !BarState.flagM
    // running 走绑定自动启停；这里只负责停后清数据
    onWantSpectrumChanged: {
        if (!wantSpectrum)
            root.bands = [];
    }

    // 重启壳时的孤儿进程进场先清掉
    Component.onCompleted: Exec.sh("pkill -f 'quickshell.*spectrum\\.py'");

    Process {
        id: proc
        running: root.wantSpectrum
        command: [Exec.scriptDir + "/spectrum.py"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var parts = String(data).trim().split(";");
                if (parts.length < 8)
                    return;
                var vals = [];
                for (var i = 0; i < parts.length && i < 16; i++) {
                    var n = parseFloat(parts[i]);
                    if (isNaN(n))
                        n = 0;
                    // 全浮点直存（0-1.5），钳位防爆，高度换算时再归一
                    vals.push(Math.max(0, Math.min(1.5, n)));
                }
                root.bands = vals;
            }
        }
        onExited: respawn.restart()
    }
    Timer {
        id: respawn
        interval: 2000
        onTriggered: { if (root.wantSpectrum && !proc.running) proc.running = true; }
    }
}
