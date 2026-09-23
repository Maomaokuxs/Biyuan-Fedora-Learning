//@ pragma UseQApplication
import QtQuick
import Quickshell
import Quickshell.Wayland
import "./bar" as BarMod
import "./dock" as DockMod
import "./components" as Comp

// 入口：双屏顶栏 + 底部居中浮动 dock
// 运行：quickshell -p <本目录>（如 ~/.config/quickshell）
// 脚本路径全部经 Exec.scriptDir（= Quickshell.configDir）拼接，不写死个人路径。
ShellRoot {
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
            margins { top: 52; left: ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.media.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.media.w / 2 }
            implicitWidth: 360
            implicitHeight: 132
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

    // 壁纸选择器 overlay：锚到壁纸 pill 下方
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.wallOpen && modelData.name === Comp.UiState.wallScreen

            Theme { id: wallTheme }

            anchors { top: true; left: true }
            margins { top: 52; left: ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.wall.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.wall.w / 2 }
            implicitWidth: 560
            implicitHeight: 480
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // 壁纸窗要吃方向键/回车/Esc，独占键盘（关窗即归还）
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            Comp.WallpaperCard {
                anchors.fill: parent
                theme: wallTheme
                onRequestClose: Comp.UiState.wallOpen = false
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
        }
    }
}
