import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../components" as Comp
import "." as BarMod

// 顶栏：完整移植 waybar 双屏配置
// 左：launcher workspaces recorder screenshot picker clipboard gammastep theme screen-power music cava mprev mplay mnext lyric
// 右：updates weather pulseaudio brightness/cpu/power-profiles/memory/network/bluetooth/battery/clock/tray/fcitx/inhibit/power
RowLayout {
    id: root
    property var theme
    property var hostWindow: null
    property string screenName: ""
    // HDMI-A-1 用 ddcutil 外接屏亮度，eDP-1 用 waybar brightness.sh
    property bool isExternal: screenName === "HDMI-A-1"
    spacing: 2

    // 整栏级入场：门开后淡入一次，加载期各 pill 静默就位不逐个乱动
    opacity: Comp.UiState.animReady ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // 显隐开关走 BarState 单相位（flag 与文本同一次产出，动画单波齐出）

    // ---------- 左组 ----------
    Comp.Pill {
        normalBg: theme.frameBg; normalFg: theme.fg
        pillText: Comp.Icons.launcher; textSize: 18
        clickLeft: "rofi -show drun"
        clickRight: "bash " + Comp.Exec.commonDir + "/toggle-left.sh"
    }
    BarMod.Workspaces { theme: root.theme; screenName: root.screenName }

    // 左侧工具组（waybar_left_hidden 折叠）：文本走共享聚合 BarState，单相位同起同落
    Comp.Pill {
        normalBg: (Comp.BarState.recC === "recording" || Comp.BarState.recC === "kernel" || Comp.BarState.recC === "many" || Comp.BarState.recC === "inhibited") ? theme.clockBg : theme.accent
        normalFg: (Comp.BarState.recC === "recording" || Comp.BarState.recC === "kernel" || Comp.BarState.recC === "many" || Comp.BarState.recC === "inhibited") ? theme.clockFg : theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.recT
        clickLeft: "~/.config/rofi/scripts/recorder.sh"
        clickRight: "pkill -INT -f gpu-screen-recorder"
        onLeftClicked: Comp.BarState.refresh()
        onRightClicked: Comp.BarState.refresh()
    }
    Comp.Pill {
        normalBg: theme.accent; normalFg: theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.shotT
        clickLeft: "bash " + Comp.Exec.commonDir + "/screenshot.sh"
    }
    Comp.Pill {
        normalBg: theme.accent; normalFg: theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.pickT
        clickLeft: "bash " + Comp.Exec.commonDir + "/pick-color.sh"
    }
    Comp.Pill {
        normalBg: theme.accent; normalFg: theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.clipT
        clickLeft: "copyq toggle"
        clickRight: "copyq eval \"clear()\" 2>/dev/null; notify-send \"剪贴板\" \"已清空\""
    }
    Comp.Pill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.gammaT
        clickLeft: "bash -c 'pkill gammastep && notify-send 护眼 已关闭 || (gammastep -O 4500 & notify-send 护眼 已开启)'"
        onLeftClicked: Comp.BarState.refresh()
    }
    Comp.Pill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.themeT
        clickLeft: "bash ~/.config/niri/scripts/toggle-theme.sh"
        onLeftClicked: Comp.BarState.refresh()
    }
    // 壁纸选择器：静态图标，无轮询，零开销；左键开 overlay 浮窗
    Comp.Pill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        anchorKey: "wallAnchorX"
        anchorScreen: root.screenName
        forceHidden: Comp.BarState.flagL
        pillText: Comp.Icons.wallpaper
        textSize: 15
        onLeftClicked: Comp.UiState.toggleWall(root.screenName)
    }
    Comp.Pill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagL
        pillText: Comp.BarState.screenT
        clickLeft: "bash " + Comp.Exec.commonDir + "/screen.sh menu"
        onLeftClicked: Comp.BarState.refresh()
    }

    // 媒体组（原生 Mpris，语义与 music.py / mpris 控制一致）
    Comp.MusicInfo {
        normalBg: theme.mediaBg; normalFg: theme.fg
        theme: root.theme; screenName: root.screenName
        musicHidden: Comp.BarState.flagM
    }
    BarMod.LevelMeter { theme: root.theme; screenName: root.screenName }
    Comp.MprisButton {
        normalBg: theme.mediaBg; normalFg: theme.fg
        mode: "prev"; musicHidden: Comp.BarState.flagM
    }
    Comp.MprisButton {
        normalBg: theme.mediaBg; normalFg: theme.fg
        mode: "toggle"; musicHidden: Comp.BarState.flagM
    }
    Comp.MprisButton {
        normalBg: theme.mediaBg; normalFg: theme.fg
        mode: "next"; musicHidden: Comp.BarState.flagM
    }
    Comp.Pill {
        normalBg: theme.mediaBg; normalFg: theme.fg
        pillText: Comp.BarState.lyricT
    }

    Item {
        Layout.fillWidth: true
        // 字形预热文本挂在这里：Item 的孩子不参与 RowLayout 排布
        // （之前直接放 Bar 里，implicitWidth 巨大把整栏顶偏），
        // 但仍会渲染，保证图标字形首帧前传好。
        Text {
            width: 1; height: 1
            opacity: 0.01
            clip: true
            font.family: theme.fontFamily
            font.pixelSize: 14
            text: Comp.Icons.launcher + Comp.Icons.power
                + Comp.Icons.musicPlaying + Comp.Icons.musicPaused
                + Comp.Icons.prev + Comp.Icons.play + Comp.Icons.pause + Comp.Icons.next
                + Comp.Icons.shuffle + Comp.Icons.loopOff + Comp.Icons.loopAll + Comp.Icons.loopOne
                + Comp.Icons.volMute + Comp.Icons.vol0 + Comp.Icons.volLow + Comp.Icons.volHigh
                + Comp.Icons.briLow + Comp.Icons.briMid + Comp.Icons.briHigh
                + Comp.Icons.cpu + Comp.Icons.mem + Comp.Icons.net
                + Comp.Icons.btOn + Comp.Icons.btOff
                + Comp.Icons.bat0 + Comp.Icons.bat1 + Comp.Icons.bat2 + Comp.Icons.bat3 + Comp.Icons.bat4
                + Comp.Icons.batCharging + Comp.Icons.coverFallback
        }
    }

    // ---------- 右组 ----------
    Comp.ScriptPill {
        baseBg: theme.accent; baseFg: theme.fg; hiBg: theme.clockBg; hiFg: theme.clockFg
        execCmd: Comp.Exec.commonDir + "/check-updates.sh"
        pollInterval: 3600000
        clickLeft: "kitty --hold sh -c 'sudo dnf upgrade'"
        clickRight: "pkill -RTMIN+8 waybar"
    }
    Comp.ScriptPill {
        id: weatherPill
        baseBg: theme.accent; baseFg: theme.fg
        execCmd: Comp.Exec.commonDir + "/weather.py"
        pollInterval: 1800000
        clickLeft: "kitty --hold curl wttr.in"
    }
    // 天气缓存（--fetch/唤醒预热）一落地就补刷，不等 30 分钟轮询；
    // 前台 exec 从不写盘，不会自激循环
    FileView {
        path: Quickshell.env("HOME") + "/.cache/by-mgr/weather.json"
        watchChanges: true
        onFileChanged: weatherPill.refresh()
    }
    Comp.AudioPill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        screenName: root.screenName
    }
    // 内接屏亮度走共享聚合；外接屏 ddc 太慢，独立 ScriptPill 保留。
    // 两块互斥显示（forceHidden），同报一个 briAnchorX（隐藏的不上报）。
    Comp.Pill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        anchorKey: "briAnchorX"
        anchorScreen: root.screenName
        forceHidden: root.isExternal
        pillText: Comp.BarState.briT
        scrollUpCmd: Comp.Exec.scriptDir + "/brightness.sh up"
        scrollDownCmd: Comp.Exec.scriptDir + "/brightness.sh down"
        clickRight: Comp.Exec.scriptDir + "/brightness.sh mid"
        onLeftClicked: { Comp.UiState.toggleBri(root.screenName, root.isExternal); Comp.BarState.refresh(); }
        onRightClicked: Comp.BarState.refresh()
        onScrollUp: Comp.BarState.refresh()
        onScrollDown: Comp.BarState.refresh()
    }
    Comp.ScriptPill {
        baseBg: theme.deviceBg; baseFg: theme.fg
        anchorKey: "briAnchorX"
        anchorScreen: root.screenName
        forceHidden: !root.isExternal
        execCmd: "bash " + Comp.Exec.scriptDir + "/brightness-external.sh"
        pollInterval: 30000
        scrollUpCmd: "ddcutil setvcp 10 + 5"
        scrollDownCmd: "ddcutil setvcp 10 - 5"
        clickRight: "ddcutil setvcp 10 50"
        onLeftClicked: Comp.UiState.toggleBri(root.screenName, root.isExternal)
    }
    Comp.Pill {
        normalBg: theme.sysmonBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagS
        pillText: Comp.BarState.cpuT
    }
    Comp.Pill {
        normalFg: (Comp.BarState.ppC === "recording" || Comp.BarState.ppC === "kernel" || Comp.BarState.ppC === "many" || Comp.BarState.ppC === "inhibited") ? theme.clockFg : theme.fg
        normalBg: (Comp.BarState.ppC === "recording" || Comp.BarState.ppC === "kernel" || Comp.BarState.ppC === "many" || Comp.BarState.ppC === "inhibited") ? theme.clockBg : theme.sysmonBg
        pillText: Comp.BarState.ppT
        clickLeft: Comp.Exec.commonDir + "/powerprofiles.sh toggle"
        onLeftClicked: Comp.BarState.refresh()
    }
    Comp.Pill {
        normalBg: theme.sysmonBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagS
        pillText: Comp.BarState.memT
        clickLeft: "kitty --title 'System Monitor' btop"
    }
    Comp.Pill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagS
        pillText: Comp.BarState.netT
        clickLeft: "kitty -e nmtui"
    }
    Comp.BluetoothPill {
        normalBg: theme.deviceBg; normalFg: theme.fg
        forceHidden: Comp.BarState.flagS
    }
    Comp.BatteryPill {
        normalBg: theme.sysmonBg; normalFg: theme.fg
    }
    // 时钟：反色锚点
    Comp.Pill {
        id: clockPill
        normalBg: theme.clockBg; normalFg: theme.clockFg; bold: true
        pillText: Qt.formatDateTime(clockDate, "hh:mm")
        property var clockDate: new Date()
        Timer { interval: 1000; running: true; repeat: true; onTriggered: clockPill.clockDate = new Date() }
    }
    // 通知铃：未读数 + 开关历史中心。无通知时用 0 占位，宽度恒定，浮窗不跳。
    // anchorKey 上报中心横坐标，toast 栈与通知中心都锚到铃铛下方
    //（缺了它 notifAnchorX 恒为 0，toast 窗会被摆到屏外——2026-09 实测）。
    Comp.Pill {
        normalBg: theme.accent; normalFg: theme.fg
        anchorKey: "notifAnchorX"
        anchorScreen: root.screenName
        pillText: Comp.Icons.bell + " " + Comp.Notifs.unread
        onLeftClicked: {
            Comp.Notifs.markRead();
            Comp.UiState.toggleNotif(root.screenName);
        }
    }
    // 托盘：与其他模块一致的圆角色块底。
    // 注意：items 是 UntypedObjectModel，没有 .count，Repeater 直接吃它也没有
    // modelData；一律走 .values（JS 数组），和 Mpris 用法一致。
    Rectangle {
        id: trayBox
        property real animW: SystemTray.items.values.length > 0 ? trayRow.implicitWidth + 12 : 0
        Behavior on animW { enabled: Comp.UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
        Behavior on opacity { enabled: Comp.UiState.animReady; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

        visible: opacity > 0.01
        opacity: SystemTray.items.values.length > 0 ? 1 : 0
        height: 32
        width: trayRow.implicitWidth + 12
        Layout.preferredWidth: animW
        Layout.preferredHeight: 32
        radius: 10
        clip: true
        color: theme.accent

        Row {
            id: trayRow
            anchors.centerIn: parent
            spacing: 4
            Repeater {
                model: SystemTray.items.values
                MouseArea {
                    id: trayMouse
                    width: 24; height: 32
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    onClicked: e => {
                        if (e.button === Qt.LeftButton) {
                            if (modelData.onlyMenu && modelData.hasMenu)
                                trayMenu.open();
                            else
                                modelData.activate();
                        } else {
                            if (modelData.hasMenu)
                                trayMenu.open();
                            else
                                modelData.secondaryActivate();
                        }
                    }
                    // 右键菜单：很多 SNI 不实现 SecondaryActivate，
                    // 必须走 DBusMenu；anchor.window 复用顶栏窗口
                    QsMenuAnchor {
                        id: trayMenu
                        anchor.window: root.hostWindow
                        anchor.item: trayMouse
                        anchor.edges: Edges.Bottom
                        anchor.gravity: Edges.Bottom
                        menu: modelData.menu
                    }
                    // tray 图标可能是主题名也可能是路径，必须用 IconImage，
                    // 普通 Image 播不了主题名会导致整块空白
                    IconImage {
                        anchors.centerIn: parent
                        implicitSize: 20
                        source: modelData.icon
                    }
                }
            }
        }
    }
    Comp.ScriptPill {
        baseBg: theme.accent; baseFg: theme.fg
        execCmd: Comp.Exec.commonDir + "/fcitx_status.sh"
        pollInterval: 1000
        clickLeft: "fcitx5-remote -s"
        clickRight: "fcitx5-configtool"
    }
    Comp.Pill {
        normalBg: (Comp.BarState.inhibitC === "recording" || Comp.BarState.inhibitC === "kernel" || Comp.BarState.inhibitC === "many" || Comp.BarState.inhibitC === "inhibited") ? theme.clockBg : theme.accent
        normalFg: (Comp.BarState.inhibitC === "recording" || Comp.BarState.inhibitC === "kernel" || Comp.BarState.inhibitC === "many" || Comp.BarState.inhibitC === "inhibited") ? theme.clockFg : theme.fg
        pillText: Comp.BarState.inhibitT
        clickLeft: "bash " + Comp.Exec.commonDir + "/inhibit.sh toggle"
        onLeftClicked: Comp.BarState.refresh()
    }
    Comp.Pill {
        normalBg: theme.frameBg; normalFg: theme.fg
        pillText: Comp.Icons.power
        clickLeft: "~/.config/rofi/scripts/powermenu.sh"
        clickRight: "bash " + Comp.Exec.commonDir + "/toggle-system.sh"
        onRightClicked: Comp.BarState.refresh()
    }
}
