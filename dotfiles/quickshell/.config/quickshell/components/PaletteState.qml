pragma Singleton

import QtQuick
import Quickshell.Io

// 调色板集中轮询：全壳每秒只 fork 一次 bash，各 Theme 实例纯绑定跟随。
// （FileView.watchChanges 在 0.2.x 对此场景静默不触发，改走这里。）
// 注：用 Item 而非 QtObject，因需容纳 Timer/Process 子对象。
Item {
    id: root
    visible: false
    property string blob: ""

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: { if (!proc.running) proc.running = true; }
    }
    Process {
        id: proc
        command: ["bash", "-c", "source ~/.cache/by-mgr/hellwal/global-palette.env 2>/dev/null && echo \"$BG:$FG:$ACCENT:$MUTED\" || echo \"\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (t.length > 0)
                    root.blob = t;
            }
        }
    }
}
