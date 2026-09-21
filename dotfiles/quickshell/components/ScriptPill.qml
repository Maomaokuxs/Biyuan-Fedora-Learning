import QtQuick
import Quickshell.Io

// 复用 waybar custom 模块：shell轮询 -> JSON {text,class,tooltip}
Pill {
    id: root
    property string execCmd: ""
    property int pollInterval: 2000
    property string pillClass: ""
    // 配色全部走绑定：命令式赋值会打断绑定，换壁纸就再也跟不上了——
    // 之前 inhibit 高亮深字压深底、fcitx 纯文本输出吃不到主题色，都是这个根因。
    // 高亮时用的反色（recording / kernel / many / inhibited），由 Bar 传入 theme 值
    property string hiBg: "#6a442f"  // FALLBACK
    property string hiFg: "#f9f3f1"  // FALLBACK
    property string baseBg: "#998c8c"  // FALLBACK: Bar 必传，此值走不到
    property string baseFg: "#6a442f"  // FALLBACK: Bar 必传，此值走不到
    property bool highlighted: pillClass === "recording" || pillClass === "kernel"
        || pillClass === "many" || pillClass === "inhibited"
    // 覆盖 Pill 的直赋值：Bar 改传 baseFg，不再传 normalBg/normalFg
    normalBg: highlighted ? hiBg : baseBg
    normalFg: highlighted ? hiFg : baseFg
    // flag 组（左侧工具/sys 组）设为 true：hidden 回执不清文本，
    // 显隐完全交给 forceHidden，取消隐藏时旧文本瞬间齐现、单段动画；
    // 否则各 pill 要等自己轮询相位（1~5s）逐个冒出来。
    // 无 flag 的 pill（lyric）保持 false，内容没了就正常折叠。
    property bool preserveTextOnHidden: false

    Timer {
        id: poller
        interval: root.pollInterval
        repeat: true
        running: root.execCmd !== ""
        triggeredOnStart: true
        onTriggered: runner.running = true
    }

    // 交互后即时补刷：滚轮/点击只管发命令不管显示，不补刷就得等下一个轮询周期
    // （内置屏 2s、外接屏 30s）。200ms 快刷 + 2.5s 慢刷（cover ddcutil 类慢命令），
    // restart() 顺带防抖，连续滚轮只刷最后一次。
    function refresh() { refreshFast.restart(); refreshSlow.restart(); }
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
    onScrollUp: root.refresh()
    onScrollDown: root.refresh()
    onLeftClicked: root.refresh()
    onRightClicked: root.refresh()
    onMiddleClicked: root.refresh()

    Process {
        id: runner
        command: ["bash", "-c", root.execCmd]
        stdout: StdioCollector {
            onStreamFinished: {
                var raw = this.text.trim();
                if (raw === "")
                    return;
                try {
                    var j = JSON.parse(raw);
                    var t = j.text !== undefined ? String(j.text) : raw;
                    var c = j.class !== undefined ? String(j.class) : "";
                    root.pillClass = c;
                    if (c === "hidden") {
                        if (!root.preserveTextOnHidden)
                            root.pillText = "";
                    } else {
                        root.pillText = t;
                    }
                } catch (e) {
                    root.pillText = raw;
                }
            }
        }
    }
}
