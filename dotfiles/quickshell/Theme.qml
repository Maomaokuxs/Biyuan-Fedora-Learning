import QtQuick
import Quickshell.Io

// Hellwal 动态配色：复用 ~/.cache/by-mgr/hellwal/global-palette.env
// 由 theme-sync.sh 生成，壁纸切换时自动更新。3s 轮询，无文件时回落浅色快照。
// 注：用 Item 而非 QtObject，因需容纳 Process/Timer 子对象（QtObject 无 default property）。
Item {
    id: root
    visible: false

    property string bg: "#f9f3f1"
    property string fg: "#6a442f"
    property string accent: "#998c8c"
    property string muted: "#b4aaa8"

    // 派生组色（对齐 waybar style.css 分组逻辑）。
    // 注意：必须是绑定而不能写死，否则换壁纸/昼夜切换时只有四个基础色会变，
    // 大半模块还停在旧配色上——这就是之前“有些控件不变色”的根因。
    property color sysmonBg: Qt.tint(root.accent, Qt.alpha(root.fg, 0.14))
    property color deviceBg: Qt.lighter(root.muted, 1.15)
    property color mediaBg: Qt.tint(root.accent, Qt.alpha(root.muted, 0.5))
    property color clockBg: root.fg
    property color clockFg: root.bg
    property color frameBg: Qt.alpha(root.muted, 0.75)

    // dock 配色：背景跟 BG（夜间近黑），按钮是压暗的壁纸色，
    // 高亮用壁纸主题色 accent 本色（不用 fg，避免夜间变成白色块）。
    // 按钮上的字/点一律用 fg（hellwal 保证 fg 与 accent 有对比）。
    property color dockBg: root.bg
    property color dockBtn: Qt.darker(root.accent, 1.35)
    property color dockHi: root.accent

    property string fontFamily: "JetBrainsMono Nerd Font"

    function reload() {
        paletteProc.running = true;
    }

    Process {
        id: paletteProc
        command: ["bash", "-c", "source ~/.cache/by-mgr/hellwal/global-palette.env 2>/dev/null && echo \"$BG:$FG:$ACCENT:$MUTED\" || echo \"\""]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (t.length > 0) {
                    var p = t.split(":");
                    if (p.length === 4) {
                        root.bg = p[0];
                        root.fg = p[1];
                        root.accent = p[2];
                        root.muted = p[3];
                        root.clockBg = p[1];
                        root.clockFg = p[0];
                    }
                }
            }
        }
    }

    Timer {
        id: poller
        interval: 3000
        running: true
        repeat: true
        onTriggered: root.reload()
    }

    Component.onCompleted: root.reload()
}
