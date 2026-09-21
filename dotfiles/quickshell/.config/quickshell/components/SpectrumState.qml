pragma Singleton

import QtQuick
import Quickshell.Io

// 真频谱服务：单例跑 spectrum.py（pw-record 直采 + numpy rfft），双屏共用一份。
// 行协议 "v0;v1;…"（12 柱 0-7），归一按帧内最大，无状态不僵死。
// 起不来时 bands 常空，调用方自行回落。
Item {
    id: root
    visible: false

    property var bands: []
    property bool fftOk: false

    // 重启壳时的孤儿进程进场先清掉
    Component.onCompleted: Exec.sh("pkill -f 'quickshell.*spectrum\\.py'");

    Process {
        id: proc
        running: true
        command: [Exec.scriptDir + "/spectrum.py"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                var parts = String(data).trim().split(";");
                if (parts.length < 8)
                    return;
                var vals = [];
                for (var i = 0; i < parts.length && i < 16; i++) {
                    var n = parseInt(parts[i], 10);
                    if (isNaN(n))
                        n = 0;
                    vals.push(Math.max(0, Math.min(1, n / 7)));
                }
                root.bands = vals;
                root.fftOk = true;
            }
        }
        onExited: respawn.restart()
    }
    Timer {
        id: respawn
        interval: 2000
        onTriggered: { if (!proc.running) proc.running = true; }
    }
}
