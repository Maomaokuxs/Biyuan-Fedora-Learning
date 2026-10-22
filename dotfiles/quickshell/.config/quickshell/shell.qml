//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "./bar" as BarMod
import "./dock" as DockMod
import "./components" as Comp

// 入口：双屏顶栏 + 底部居中浮动 dock
// 运行：quickshell -p <本目录>（如 ~/.config/quickshell）
// 脚本路径全部经 Exec.scriptDir（= Quickshell.configDir）拼接，不写死个人路径。
ShellRoot {
    // IPC：Mod+Shift+W 直达壁纸选择器（niri 绑定调 quickshell ipc call wallpaper openWallpaper）。
    // 本 quickshell 版本 QML 解析器不支持函数参数类型注解，IPC 带参会报 QVariant 无法跨 IPC，
    // 故用无参函数 + 内部 Process 查 `niri msg focused-output`（quickshell 由 niri 拉起，自带 NIRI_SOCKET）。
    // 查不到/不在屏列表里时回落主屏。
    IpcHandler {
        target: "wallpaper"
        function openWallpaper(): void {
            focusQuery.running = true;
        }
    }
    Process {
        id: focusQuery
        command: ["bash", "-c", "niri msg focused-output 2>/dev/null | grep -m1 -oP '\\(\\K[^)]+' | head -1"]
        stdout: StdioCollector {
            onStreamFinished: {
                var s = this.text.trim();
                var ok = false;
                for (var i = 0; i < Quickshell.screens.length; i++) {
                    if (Quickshell.screens[i].name === s) { ok = true; break; }
                }
                if (!ok) {
                    for (var j = 0; j < Quickshell.screens.length; j++) {
                        if (Quickshell.screens[j].isMainScreen) { s = Quickshell.screens[j].name; break; }
                    }
                }
                if (s === "")
                    s = Quickshell.screens[0].name;
                Comp.UiState.toggleWallpaperPicker(s);
            }
        }
    }

    // 护眼模式持久化恢复：启动时读 ~/.cache/by-mgr/gammastep-on，为 1 则恢复开启。
    // 脚本内部 sleep 5 后台执行，不卡启动关键路径；已开则不重复起。
    Process {
        command: ["bash", Comp.Exec.commonDir + "/gammastep-restore.sh"]
        running: true
    }

    // 注意：Variants delegate 是隔离作用域，外层 id 直接引用会 undefined，
    // 故每个 PanelWindow 内各自实例化 Theme。
    Variants {
        model: Quickshell.screens

        PanelWindow {
            id: barWin
            required property var modelData
            screen: modelData

            Theme { id: barTheme }

            // 全宽顶栏：窗口本身贴合显示器（margins 0），内边距放在 Bar 内部，
            // 之前 left/right 各 4 的窗口 margins 会让整条 bar 比显示器窄 8px。
            anchors { top: true; left: true; right: true }
            margins { top: 0; left: 0; right: 0; bottom: 0 }
            exclusionMode: ExclusionMode.Auto
            exclusiveZone: 46
            implicitHeight: 46
            color: barTheme.bg

            BarMod.Bar {
                anchors.fill: parent
                anchors.leftMargin: 4
                anchors.rightMargin: 4
                anchors.topMargin: 7
                anchors.bottomMargin: 7
                theme: barTheme
                hostWindow: barWin
                screenName: modelData.name
            }
        }
    }

    // 胶囊拖拽幽灵覆盖窗（Overlay 层全宽透明窗）：只在本屏拖拽进行时可见，
    // 幽灵画在栏窗口之上，不被栏的裁剪/布局约束。mask 空 Region = 输入全穿透，
    // 拖拽事件仍由栏内 pill 的 MouseArea 独占。坐标与栏窗口同原点
    // （同屏、同顶边、同左锚定、margins 0）；高度 160 容许指针拖出栏下沿。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.dragActive && Comp.UiState.dragScreen === modelData.name

            anchors { top: true; left: true; right: true }
            margins { top: 0; left: 0; right: 0 }
            implicitHeight: 160
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { }

            Rectangle {
                width: Comp.UiState.dragW
                height: 32
                radius: 10
                opacity: 0.92
                color: Comp.UiState.dragBg
                x: Comp.UiState.dragX - width / 2
                y: Comp.UiState.dragY - 16
                Text {
                    anchors.centerIn: parent
                    text: Comp.UiState.dragText
                    color: Comp.UiState.dragFg
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 14
                }
            }
        }
    }

    // 播放卡 overlay（anomshell 模式：Overlay 层 + Ignore，不占位不挤窗口，
    // PopupWindow 在 niri 下静默不可见，故改此模式；卡片本体见 MediaPlayer.qml）
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.mediaOpen && modelData.name === Comp.UiState.mediaScreen

            Theme { id: cardTheme }

            anchors { top: true; left: true }
            margins { top: 42; left: ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.media.anchor] || {})[modelData.name] || 0) - 95 }
            implicitWidth: 320
            implicitHeight: 300
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.MediaPlayer {
                anchors.fill: parent
                theme: cardTheme
                onRequestClose: Comp.UiState.mediaOpen = false
            }
        }
    }

    // 电平浮窗 overlay（同上）
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.vizOpen && modelData.name === Comp.UiState.vizScreen

            Theme { id: vizTheme }

            anchors { top: true; left: true }
            // 居中锚定 + 屏幕边缘钳制：左侧收起后 pill 左移，anchor-w/2 会成负数；
            // modelData.width 兜底 99999（取不到时退化为只钳左缘，原行为不变）
            margins { top: 52; left: Math.max(0, Math.min(((Comp.UiState.anchorMap[Comp.UiState.popupGeom.viz.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.viz.w / 2, (modelData.width || 99999) - Comp.UiState.popupGeom.viz.w)) }
            implicitWidth: 480
            // 卡片高度跟内容走（dance 模式多一排编排选项）
            implicitHeight: vizCard.implicitHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.VizCard {
                id: vizCard
                anchors.fill: parent
                theme: vizTheme
                onRequestClose: Comp.UiState.vizOpen = false
            }
        }
    }

    // 音量滑动条 overlay：锚到音量 pill 下方
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.volOpen && modelData.name === Comp.UiState.volScreen

            Theme { id: volTheme }

            anchors { top: true; left: true }
            margins { top: 52; left: ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.vol.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.vol.w / 2 }
            implicitWidth: 280
            implicitHeight: 68
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.VolCard {
                anchors.fill: parent
                theme: volTheme
                onRequestClose: Comp.UiState.volOpen = false
            }
        }
    }

    // 通知 toast 栈（右上，主屏）：右缘对齐，不依赖铃铛锚点；
    // server 过期自动收，点击手动 dismiss
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: modelData.isMainScreen !== false && Comp.Notifs.server.trackedNotifications.values.length > 0

            Theme { id: toastTheme }

            anchors { top: true; right: true }
            margins { top: 52; right: 12 }
            implicitWidth: 380
            implicitHeight: toastStack.implicitHeight
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.Toasts {
                id: toastStack
                anchors.top: parent.top
                anchors.right: parent.right
                width: 380
                theme: toastTheme
            }
        }
    }

    // 通知中心 overlay
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.notifOpen && modelData.name === Comp.UiState.notifScreen

            Theme { id: notifTheme }

            anchors { top: true; left: true }
            margins { top: 52; left: (Comp.UiState.notifSnap[modelData.name] || 0) - 210 }
            implicitWidth: 420
            implicitHeight: 480
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.NotifCenter {
                anchors.fill: parent
                theme: notifTheme
                onRequestClose: Comp.UiState.notifOpen = false
            }
        }
    }

    // 亮度滑动条 overlay：锚到亮度 pill 下方
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.briOpen && modelData.name === Comp.UiState.briScreen

            Theme { id: briTheme }

            anchors { top: true; left: true }
            margins { top: 52; left: ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.bri.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.bri.w / 2 }
            implicitWidth: 280
            implicitHeight: 68
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.BriCard {
                anchors.fill: parent
                theme: briTheme
                isExternal: Comp.UiState.briExternal
                onRequestClose: Comp.UiState.briOpen = false
            }
        }
    }

    // 控制中心 overlay：标签页 + 滑杆 + 开关（rofi 做不了的三件套）。
    // 锚 pill 中心，左右缘钳制（VizCard 同款：直接下标 + Math 钳位，不包方法）。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.ccOpen && modelData.name === Comp.UiState.ccScreen

            Theme { id: ccTheme }

            anchors { top: true; left: true }
            margins { top: 52; left: Math.max(0, Math.min(((Comp.UiState.anchorMap[Comp.UiState.popupGeom.cc.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.cc.w / 2, (modelData.width || 99999) - Comp.UiState.popupGeom.cc.w)) }
            implicitWidth: 460
            implicitHeight: 470
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

            Comp.ControlCenter {
                anchors.fill: parent
                theme: ccTheme
                onRequestClose: Comp.UiState.ccOpen = false
            }
        }
    }

    // 设置边栏 C 精修版 overlay（新增，原 6 个 overlay 全部保留）：
    // 右侧临时滑出，窄态 460 / 壁纸态 760，宽动画 250ms。滑块 pill 左键走边栏，替换原控制中心入口。
    // 点击空白关闭：背景与卡片同窗（背景 MouseArea 在卡片之前声明，QML 顺序保证卡片在上），
    // 不再用独立全屏背景窗——独立背景窗在 niri 里会盖到边栏上，吃掉边栏内点击
    // （点壁纸行反而关边栏、“壁纸窗口无法进入”的回归根因，2026-10-14 修）。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.sidebarOpen && modelData.name === Comp.UiState.sidebarScreen

            Theme { id: sidebarTheme }

            // 全屏（顶留 46 不遮顶栏）：背景点空白 + 卡片同窗
            anchors { top: true; left: true; right: true; bottom: true }
            margins { top: 46; left: 0; right: 0; bottom: 0 }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // 独占键盘以接 Esc（壁纸卡同款）；关边栏即归还
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // 背景：点空白关闭。声明在卡片之前，卡片在上，点卡片/滑杆不会误触。
            MouseArea {
                anchors.fill: parent
                onClicked: {
                    Comp.UiState.sidebarOpen = false;
                    Comp.UiState.sidebarWallpaper = false;
                }
            }

            // 卡片：右侧滑出
            Item {
                id: sidebarWrap
                anchors { top: parent.top; right: parent.right; bottom: parent.bottom }
                anchors.topMargin: 6
                anchors.rightMargin: 12
                anchors.bottomMargin: 12
                width: Comp.UiState.sidebarWallpaper ? 760 : 460
                Behavior on width { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                focus: true
                // 入场：从右侧滑入（Translate，不与 width 动画抢 x）
                property real slideIn: Comp.UiState.sidebarOpen ? 0 : 1
                Behavior on slideIn { NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
                transform: Translate { x: sidebarWrap.slideIn * (sidebarWrap.width + 12) }
                // Esc：壁纸态先回窄态，再 Esc 关闭，与 ← 返回一致
                Keys.onEscapePressed: {
                    if (Comp.UiState.sidebarWallpaper)
                        sidebarContent.exitWallpaper();
                    else {
                        Comp.UiState.sidebarOpen = false;
                        Comp.UiState.sidebarWallpaper = false;
                    }
                }

                Comp.SettingsSidebar {
                    id: sidebarContent
                    anchors.fill: parent
                    theme: sidebarTheme
                    onRequestClose: {
                        Comp.UiState.sidebarOpen = false;
                        Comp.UiState.sidebarWallpaper = false;
                    }
                }
            }
        }
    }

    // 极简壁纸选择器 overlay（独立居中窗口，不进边栏，不叠层，不全屏）：
    // 900×600 居中窗口（组件内 Theme.bg 背景，圆角 16），不铺壁纸全屏（防头晕）。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.wallpaperPickerOpen && modelData.name === Comp.UiState.wallpaperPickerScreen

            Theme { id: zzzTheme }

            property real winW: Math.min(900, (modelData.width || 900) * 0.9)
            property real winH: Math.min(600, (modelData.height || 600) * 0.9)
            anchors { top: true; left: true }
            margins { top: ((modelData.height || 600) - winH) / 2; left: ((modelData.width || 900) - winW) / 2 }
            implicitWidth: winW
            implicitHeight: winH
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // 壁纸窗要吃方向键/回车/Esc/滚轮，独占键盘（关窗即归还，壁纸卡同款）
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Comp.WallpaperPicker {
                anchors.fill: parent
                theme: zzzTheme
                onRequestClose: Comp.UiState.wallpaperPickerOpen = false
            }
        }
    }

    // dock 仅主屏底部居中悬浮 + 自动隐藏：
    // exclusionMode.Ignore → 纯 overlay，不占 exclusiveZone，不挤占窗口；
    // 隐藏时整窗下沉只留 6px 窥视条，HoverHandler 悬停即滑出，离开 800ms 后滑回。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: modelData.isMainScreen !== false

            Theme { id: dockTheme }

            id: dockWin
            property bool dockHidden: true
            property bool paletteTimeout: false
            // 最近一次 dock 交互时间戳：点击会导致窗口重排、hover 抖动，
            // 保护期内即使 hover 闪断也不收，保证可连续点两下。
            property double lastDockInteract: 0

            anchors { bottom: true }
            exclusionMode: ExclusionMode.Ignore
            margins {
                bottom: dockWin.dockHidden ? -(dockWin.implicitHeight - 6) : 10
                Behavior on bottom { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
            }
            // + gapExtra：拖拽时多留一个槽位宽，空隙位移不裁图标；平时为 0
            implicitWidth: dockRow.implicitWidth + 32 + dockRow.gapExtra
            // 76 = 按钮 48 + 底部边距 8 + 顶部 20（拖拽提起 10 + 放大溢出约 5，免裁剪）
            implicitHeight: 76
            color: "transparent"

            Timer {
                id: hideTimer
                interval: 800
                onTriggered: {
                    if (Date.now() - dockWin.lastDockInteract < 2000) hideTimer.restart();
                    else dockWin.dockHidden = true;
                }
            }

            // 内容层：启动淡入（与顶栏同门控），PanelWindow 本身无 opacity 属性
            Item {
                anchors.fill: parent
                opacity: (Comp.UiState.animReady && (Comp.PaletteState.blob !== "" || dockWin.paletteTimeout)) ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

            // 背景跟主题 BG（夜间近黑），不透明度保留悬停反馈。
            Rectangle {
                anchors { left: parent.left; right: parent.right; bottom: parent.bottom }
                height: 64
                radius: 20
                color: dockTheme.dockBg
                opacity: dockWin.dockHidden ? 0.4 : 0.75
            }
            // 隐藏态提示 pill：窗体隐藏时露出来的是顶部 6px（底部锚定 + 负 margin
            // 把窗体往下推），所以 pill 必须锚顶部；双色（浅芯 + 深边）在深浅壁纸下都可见。
            Rectangle {
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.top: parent.top
                anchors.topMargin: 1
                width: 140
                height: 5
                radius: 2.5
                color: dockTheme.clockFg
                border.width: 1
                border.color: dockTheme.clockBg
                opacity: dockWin.dockHidden ? 0.95 : 0
                Behavior on opacity { NumberAnimation { duration: 200 } }
            }
            // 全窗 hover 检测（含标题浮层区）：放透明 Item 上，和背景视觉分离，
            // 鼠标移到标题上时 dock 不会收回。
            Item {
                anchors.fill: parent
                HoverHandler {
                    onHoveredChanged: {
                        if (hovered) {
                            hideTimer.stop();
                            dockWin.lastDockInteract = Date.now();
                            dockWin.dockHidden = false;
                        } else {
                            hideTimer.restart();
                        }
                    }
                }
            }
            DockMod.Dock {
                id: dockRow
                anchors.horizontalCenter: parent.horizontalCenter
                anchors.bottom: parent.bottom
                anchors.bottomMargin: 8
                theme: dockTheme
                onInteracted: {
                    dockWin.lastDockInteract = Date.now();
                    hideTimer.stop();
                    dockWin.dockHidden = false;
                }
            }
            } // 内容层

            Timer {
                interval: 5000
                running: true
                onTriggered: dockWin.paletteTimeout = true
            }
        }
    }
}
