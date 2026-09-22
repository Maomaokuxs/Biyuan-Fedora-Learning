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
    // flag 翻转（外部 rofi 菜单切的）立刻补刷一次，文本不等下个 2s 周期，
    // 显隐只差一次快刷（200ms），和 forceHidden 变化几乎同时到位
    onFlagLChanged: refreshFast.restart()
    onFlagSChanged: refreshFast.restart()
    onFlagMChanged: refreshFast.restart()
    // 启动动画门：放行前所有 pill 静默就位（替代 Flags 的 6×500ms 门）
    property int runs: 0

    // 显示合并：数据到后暂存，250ms 窗口一到统一落盘——
    // 不管哪个 pill 先到后到，动画永远同一波播出去
    property var pending: null
    function field(o, k, f) {
        try {
            var v = o[k] ? o[k][f] : "";
            return v === undefined || v === null ? "" : String(v);
        } catch (e) {
            return "";
        }
    }
    function stageFull(o) {
        root.pending = o;
        applyTimer.restart();
    }
    function stageOne(k, j) {
        var p = {};
        var old = root.pending;
        if (old) {
            for (var key in old)
                p[key] = old[key];
        }
        p[k] = j;
        root.pending = p;
        applyTimer.restart();
    }
    function applyPending() {
        var o = root.pending;
        root.pending = null;
        if (!o)
            return;
        try {
            if ("rec" in o) { root.recT = root.field(o, "rec", "text"); root.recC = root.field(o, "rec", "class"); }
            if ("shot" in o) { root.shotT = root.field(o, "shot", "text"); root.shotC = root.field(o, "shot", "class"); }
            if ("pick" in o) { root.pickT = root.field(o, "pick", "text"); root.pickC = root.field(o, "pick", "class"); }
            if ("clip" in o) { root.clipT = root.field(o, "clip", "text"); root.clipC = root.field(o, "clip", "class"); }
            if ("gamma" in o) { root.gammaT = root.field(o, "gamma", "text"); root.gammaC = root.field(o, "gamma", "class"); }
            if ("screen" in o) { root.screenT = root.field(o, "screen", "text"); root.screenC = root.field(o, "screen", "class"); }
            if ("lyric" in o) { root.lyricT = root.field(o, "lyric", "text"); root.lyricC = root.field(o, "lyric", "class"); }
            if ("bri" in o) { root.briT = root.field(o, "bri", "text"); root.briC = root.field(o, "bri", "class"); }
            if ("cpu" in o) { root.cpuT = root.field(o, "cpu", "text"); root.cpuC = root.field(o, "cpu", "class"); }
            if ("mem" in o) { root.memT = root.field(o, "mem", "text"); root.memC = root.field(o, "mem", "class"); }
            if ("net" in o) { root.netT = root.field(o, "net", "text"); root.netC = root.field(o, "net", "class"); }
            if ("inhibit" in o) { root.inhibitT = root.field(o, "inhibit", "text"); root.inhibitC = root.field(o, "inhibit", "class"); }
            if ("theme" in o) { root.themeT = root.field(o, "theme", "text"); root.themeC = root.field(o, "theme", "class"); }
            if ("pp" in o) { root.ppT = root.field(o, "pp", "text"); root.ppC = root.field(o, "pp", "class"); }
            if ("flagL" in o) root.flagL = o.flagL === 1;
            if ("flagS" in o) root.flagS = o.flagS === 1;
            if ("flagM" in o) root.flagM = o.flagM === 1;
            if (!UiState.animReady && ++root.runs >= 2)
                UiState.animReady = true;
        } catch (e) {}
    }
    Timer {
        id: applyTimer
        interval: 150
        onTriggered: root.applyPending()
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
                    root.stageFull(JSON.parse(this.text));
                } catch (e) {}
            }
        }
    }

    function refresh() {
        refreshFast.restart();
        refreshSlow.restart();
    }
    // 定点补刷：只跑被点的那一个脚本（十几毫秒），不等 350ms 的全量聚合。
    // key 即字段名前缀（rec/gamma/screen/bri/pp/inhibit/theme），cmd 与聚合内同源。
    // 单发串行：连点只保留最后一次，中途的杀掉（用户手速下无感）。
    property string oneKey: ""
    property string oneCmd: ""
    function refreshOne(key, cmd) {
        root.oneKey = key;
        root.oneCmd = cmd;
        oneRunner.running = false;
        oneRunner.running = true;
    }
    Process {
        id: oneRunner
        command: ["bash", "-c", root.oneCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                try {
                    root.stageOne(root.oneKey, JSON.parse(this.text));
                } catch (e) {}
            }
        }
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
