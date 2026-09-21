pragma Singleton

import QtQuick
import Quickshell.Io

// 共享快查状态：单一定时器 + 单进程（bar-fast.sh）替代 13 个 ScriptPill 独立轮询。
// 双屏 Bar 共用一份（输出与屏幕无关；外屏亮度走 ddc 太慢，仍独立轮询）。
// 交互后调 refresh() 即时补刷（200ms 快刷 + 2.5s 慢刷），与 ScriptPill.refresh 同语义。
Item {
    id: root
    visible: false

    property string recT: ""
    property string recC: ""
    property string shotT: ""
    property string shotC: ""
    property string pickT: ""
    property string pickC: ""
    property string clipT: ""
    property string clipC: ""
    property string gammaT: ""
    property string gammaC: ""
    property string screenT: ""
    property string screenC: ""
    property string lyricT: ""
    property string lyricC: ""
    property string briT: ""
    property string briC: ""
    property string cpuT: ""
    property string cpuC: ""
    property string memT: ""
    property string memC: ""
    property string netT: ""
    property string netC: ""
    property string inhibitT: ""
    property string inhibitC: ""
    property string themeT: ""
    property string themeC: ""
    property string ppT: ""
    property string ppC: ""
    // 显隐 flag（与文本同一次产出、同一相位，动画单波齐出，替代 Flags.qml 的 500ms 独立时钟）
    property bool flagL: false
    property bool flagS: false
    property bool flagM: false
    // 启动动画门：放行前所有 pill 静默就位（替代 Flags 的 6×500ms 门）
    property int runs: 0

    function field(o, k, f) {
        try {
            var v = o[k] ? o[k][f] : "";
            return v === undefined || v === null ? "" : String(v);
        } catch (e) {
            return "";
        }
    }

    Timer {
        id: poller
        interval: 2000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!runner.running) runner.running = true; }
    }
    Process {
        id: runner
        command: ["bash", Exec.scriptDir + "/bar-fast.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    var o = JSON.parse(this.text);
                    root.recT = root.field(o, "rec", "text");
                    root.recC = root.field(o, "rec", "class");
                    root.shotT = root.field(o, "shot", "text");
                    root.shotC = root.field(o, "shot", "class");
                    root.pickT = root.field(o, "pick", "text");
                    root.pickC = root.field(o, "pick", "class");
                    root.clipT = root.field(o, "clip", "text");
                    root.clipC = root.field(o, "clip", "class");
                    root.gammaT = root.field(o, "gamma", "text");
                    root.gammaC = root.field(o, "gamma", "class");
                    root.screenT = root.field(o, "screen", "text");
                    root.screenC = root.field(o, "screen", "class");
                    root.lyricT = root.field(o, "lyric", "text");
                    root.lyricC = root.field(o, "lyric", "class");
                    root.briT = root.field(o, "bri", "text");
                    root.briC = root.field(o, "bri", "class");
                    root.cpuT = root.field(o, "cpu", "text");
                    root.cpuC = root.field(o, "cpu", "class");
                    root.memT = root.field(o, "mem", "text");
                    root.memC = root.field(o, "mem", "class");
                    root.netT = root.field(o, "net", "text");
                    root.netC = root.field(o, "net", "class");
                    root.inhibitT = root.field(o, "inhibit", "text");
                    root.inhibitC = root.field(o, "inhibit", "class");
                    root.themeT = root.field(o, "theme", "text");
                    root.themeC = root.field(o, "theme", "class");
                    root.ppT = root.field(o, "pp", "text");
                    root.ppC = root.field(o, "pp", "class");
                    root.flagL = o.flagL === 1;
                    root.flagS = o.flagS === 1;
                    root.flagM = o.flagM === 1;
                    if (!UiState.animReady && ++root.runs >= 2)
                        UiState.animReady = true;
                } catch (e) {}
            }
        }
    }

    function refresh() {
        refreshFast.restart();
        refreshSlow.restart();
    }
    Timer {
        id: refreshFast
        interval: 200
        onTriggered: { if (!runner.running) runner.running = true; }
    }
    Timer {
        id: refreshSlow
        interval: 2500
        onTriggered: { if (!runner.running) runner.running = true; }
    }
}
