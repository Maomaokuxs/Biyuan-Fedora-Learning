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

    // IPC：天气面板开关（niri 可绑定 quickshell ipc call weather toggleWeatherPanel）。
    // 与 wallpaper 同款无参 + 查聚焦屏模式（本版 IPC 不支持带参函数）。
    IpcHandler {
        target: "weather"
        function toggleWeatherPanel(): void {
            weatherFocusQuery.running = true;
        }
    }
    Process {
        id: weatherFocusQuery
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
                Comp.UiState.toggleWeather(s);
            }
        }
    }

    // IPC：顶栏方向查询/设置（niri 可绑定 quickshell ipc call bar toBottom 等）。
    // 本版 IPC 不支持带参函数，故方向用四个无参 setter；getter 返回当前方向串。
    IpcHandler {
        target: "bar"
        function direction(): string {
            return Comp.UiState.barDirection;
        }
        function toTop(): void { Comp.UiState.setBarDirection("top"); }
        function toBottom(): void { Comp.UiState.setBarDirection("bottom"); }
        function toLeft(): void { Comp.UiState.setBarDirection("left"); }
        function toRight(): void { Comp.UiState.setBarDirection("right"); }
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
            // 方向：top/bottom 贴上下边（bottom 时栏带在窗下部、抽屉与面板向
            // 屏内上方展开）；left/right 由第二段接管（贴左右边、竖条）。
            property string barDir: Comp.UiState.barDirection
            property bool barBottom: barDir === "bottom"
            // 竖条：left/right 贴左右边、栏宽 56、抽屉条宽 56、缝 6；
            // 窗宽开 118=56+6+56、关 56（与横向 winH 94/46 对偶）
            property bool barVertical: barDir === "left" || barDir === "right"
            property bool barLeft: barDir === "left"
            // 栏带在窗内的 y：top 为 0；bottom 为 winH-46（开 94 时 48、关 46 时 0，
            // 关着时窗高即栏高、栏带仍在窗内底部，几何自洽）
            property int barBandY: barBottom ? winH - 46 : 0
            property int barBandX: barLeft ? 0 : winW - 56
            anchors { top: barDir !== "bottom"; bottom: barDir !== "top"; left: barDir !== "right"; right: barDir !== "left" }
            margins { top: 0; left: 0; right: 0; bottom: 0 }
            exclusionMode: ExclusionMode.Auto
            exclusiveZone: barVertical ? 56 : 46
            // 窗高固定 46+6+42：下方 42 是收纳抽屉的预留条带，中间 6 是
            // 抽屉与顶栏之间的缝。堆叠式：抽屉平时整条藏在栏底色背后
            // （y=4 时全部落在栏区内、被上层栏底色盖住）；打开时从顶栏
            // 背后向下滑动到 y=52（46 栏 + 6 缝），关闭时原路滑回栏后，
            // 280ms 后窗口缩回 46（下方条带随即消失、点击穿透恢复——
            // 无 mask，靠窗口本身尺寸限定输入区；本构建 Region 的
            // Rect 子类型不可用，故不用 mask 方案。）
            // exclusiveZone 仍是 46，普通窗口的可用区不变。
            color: "transparent"
            property bool stowOpenHere: Comp.UiState.stowOpen && Comp.UiState.stowScreen === modelData.name
            // 抽屉条带是否参与事件与渲染：打开瞬间置 true；关闭滑动播完
            // （shrinkTimer 280ms）后才置 false，期间条带已完全藏回栏后。
            property bool drawerVisible: false
            property int winH: 46
            property int winW: 56
            implicitHeight: winH
            implicitWidth: winW
            onStowOpenHereChanged: {
                if (stowOpenHere) {
                    drawerVisible = true;
                    winH = 94;
                    winW = 118;
                } else {
                    shrinkTimer.restart();
                }
            }
            Component.onCompleted: {
                if (stowOpenHere) {
                    drawerVisible = true;
                    winH = 94;
                    winW = 118;
                }
            }
            Timer {
                id: shrinkTimer
                interval: 280
                onTriggered: {
                    if (!barWin.stowOpenHere) {
                        barWin.winH = 46;
                        barWin.winW = 56;
                        barWin.drawerVisible = false;
                    }
                }
            }

            // 背景拖手势（抽屉持久开关 + 搬家）：位于全部内容之下，
            // 胶囊/工作区/音乐等内容都在其上、先拿到自己的事件，不受影响；
            // 纯点击不触发任何事。向屏内分量：左栏 dx、右栏 -dx、顶栏 dy、
            // 底栏 -dy。向屏内拉过 24px → 本屏抽屉持久打开；向屏外拉过
            // 24px → 关闭（一次按压只触发一次开关）；继续向屏内拉过
            // 110px → 搬家模式（栏浮起 + 目标边停靠预览，指针最近边实时
            // 更新）；松手：搬家模式下停靠最近边（同边不换方向、抽屉保持
            // 24px 处已开的状态），未进搬家则按 24px 开关结果处理。
            // 注意：拉过 110px 时指针已出栏窗（开抽屉时窗高仅 94/窗宽仅
            // 118），靠 MouseArea 的按压抓取继续收事件，松手才放。
            MouseArea {
                anchors.fill: parent
                z: 0
                property real pressY: 0
                property real pressX: 0
                property bool fired: false
                property bool moveStarted: false
                onPressed: { pressY = mouse.y; pressX = mouse.x; fired = false; moveStarted = false; }
                onPositionChanged: {
                    var dy = mouse.y - pressY;
                    var dx = mouse.x - pressX;
                    // 向屏内分量：左栏 dx、右栏 -dx、顶栏 dy、底栏 -dy
                    var inward = barWin.barLeft ? dx : barWin.barVertical ? -dx : barWin.barBottom ? -dy : dy;
                    if (moveStarted) {
                        // 搬家进行中：只更新最近边（屏坐标 = 窗坐标 + 窗原点；
                        // 顶/左原点 0，底为屏高-窗高、右为屏宽-窗宽）
                        var ox = barWin.barDir === "right" ? (modelData.width || 0) - barWin.winW : 0;
                        var oy = barWin.barBottom ? (modelData.height || 0) - barWin.winH : 0;
                        var sx = mouse.x + ox;
                        var sy = mouse.y + oy;
                        var sw = modelData.width || 0;
                        var sh = modelData.height || 0;
                        var dT = sy, dB = sh - sy, dL = sx, dR = sw - sx;
                        var edge = "top", best = dT;
                        if (dB < best) { edge = "bottom"; best = dB; }
                        if (dL < best) { edge = "left"; best = dL; }
                        if (dR < best) { edge = "right"; best = dR; }
                        Comp.UiState.moveEdge = edge;
                        return;
                    }
                    if (!fired) {
                        if (inward > 24 && !barWin.stowOpenHere) {
                            fired = true;
                            Comp.UiState.stowScreen = modelData.name;
                            Comp.UiState.stowPersistent = true;
                            Comp.UiState.stowOpen = true;
                            Comp.UiState.cancelStowClose();
                        } else if (inward < -24 && barWin.stowOpenHere) {
                            fired = true;
                            Comp.UiState.stowOpen = false;
                            Comp.UiState.stowPersistent = false;
                            Comp.UiState.cancelStowClose();
                        }
                    }
                    if (inward > 110) {
                        moveStarted = true;
                        Comp.UiState.moveScreen = modelData.name;
                        Comp.UiState.moveEdge = barWin.barDir;
                        Comp.UiState.moveActive = true;
                    }
                }
                onReleased: {
                    if (moveStarted) {
                        moveStarted = false;
                        Comp.UiState.moveActive = false;
                        if (Comp.UiState.moveEdge !== barWin.barDir)
                            Comp.UiState.setBarDirection(Comp.UiState.moveEdge);
                    }
                }
            }

            // 栏底色（原窗口 color 的角色）：只盖栏带 46，z=3 在抽屉与阴影之上，
            // 抽屉滑动过程中栏区内的部分始终被它盖住（堆叠压盖关系）。
            // bottom 时栏带在窗下部（y=barBandY），其余与 top 同构。
            Rectangle {
                x: barWin.barVertical ? barWin.barBandX : 0
                y: barWin.barVertical ? 0 : barWin.barBandY
                width: barWin.barVertical ? 56 : parent.width
                height: barWin.barVertical ? parent.height : 46
                z: 3
                // 搬家浮起提示：本屏搬家时底色微亮（与 scale 1.03 同款触发）
                color: (Comp.UiState.moveActive && Comp.UiState.moveScreen === modelData.name) ? Qt.lighter(barTheme.bg, 1.08) : barTheme.bg
            }

            // 顶栏投在抽屉上的阴影：固定在栏带朝抽屉的那边、高 12，黑色由 0.28
            // 向抽屉方向淡到全透明；只在抽屉可见期间显示，关闭后窗口缩回 46、
            // 它自然在窗外。z=2 在抽屉之上、栏底色之下，阴影落在抽屉顶部。
            // bottom 时阴影在栏带上方（y=barBandY-12）、渐变方向上下颠倒。
            Rectangle {
                x: barWin.barVertical ? (barWin.barLeft ? 56 : barWin.winW - 68) : 0
                y: barWin.barVertical ? 0 : (barWin.barBottom ? barWin.barBandY - 12 : 46)
                width: barWin.barVertical ? 12 : parent.width
                height: barWin.barVertical ? parent.height : 12
                z: 2
                visible: barWin.drawerVisible
                gradient: Gradient {
                    orientation: barWin.barVertical ? Gradient.Horizontal : Gradient.Vertical
                    GradientStop { position: 0.0; color: barWin.barVertical ? (barWin.barLeft ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0)) : (barWin.barBottom ? Qt.rgba(0, 0, 0, 0) : Qt.rgba(0, 0, 0, 0.28)) }
                    GradientStop { position: 1.0; color: barWin.barVertical ? (barWin.barLeft ? Qt.rgba(0, 0, 0, 0) : Qt.rgba(0, 0, 0, 0.28)) : (barWin.barBottom ? Qt.rgba(0, 0, 0, 0.28) : Qt.rgba(0, 0, 0, 0)) }
                }
            }

            BarMod.Bar {
                id: barInst
                x: barWin.barVertical ? barWin.barBandX : 4
                y: barWin.barVertical ? 0 : barWin.barBandY + 7
                width: barWin.barVertical ? 56 : parent.width - 8
                height: barWin.barVertical ? parent.height : 32
                // 搬家浮起提示：本屏搬家时栏整体轻微缩放浮起（供用户评判手感）
                scale: (Comp.UiState.moveActive && Comp.UiState.moveScreen === modelData.name) ? 1.03 : 1
                Behavior on scale { NumberAnimation { duration: 150 } }
                z: 4
                theme: barTheme
                hostWindow: barWin
                screenName: modelData.name
            }

            // 收纳抽屉（堆叠式）：由「高度生长」改为「位置滑动」。top 时平时整条
            // 藏在栏底色背后（y=4 时 4-46 全部落在栏区内、被 z=3 的栏底色
            // 盖住、视觉上完全不可见）；打开时从顶栏背后向下滑动到 y=52
            // （46 栏 + 6 缝后的打开位），关闭时原路滑回。bottom 时镜像：
            // 平时藏在栏带背后（y=52 时 52-94 落在栏带 48-94 内），打开时
            // 从栏背后向上滑动到 y=0（42 抽屉 + 6 缝在栏带上方），关闭原路
            // 滑回。y 动画在动画启动时按 stowOpenHere 取时长与曲线（打开
            // 250ms OutCubic、关闭 180ms InCubic，退出更快原路收回）。开关只认背景纵拖
            // 手势（见上方手势层），点背景不再关闭。左收纳槽（ToolsGroup
            // 的 delegate/模型）与右收纳槽（Bar 的）同排陈列，其后是整块
            // 收纳的 holder（启动器/工作区/音乐簇/托盘，固定顺序，Bar 的
            // blockOrder）。
            Item {
                id: stowStrip
                x: barWin.barVertical ? (barWin.stowOpenHere ? (barWin.barLeft ? 62 : barWin.winW - 118) : (barWin.barLeft ? 0 : barWin.winW - 56)) : 0
                y: barWin.barVertical ? 0 : (barWin.stowOpenHere ? (barWin.barBottom ? 0 : 52) : (barWin.barBottom ? 52 : 4))
                Behavior on x {
                    NumberAnimation {
                        duration: barWin.stowOpenHere ? 250 : 180
                        easing.type: barWin.stowOpenHere ? Easing.OutCubic : Easing.InCubic
                    }
                }
                Behavior on y {
                    NumberAnimation {
                        duration: barWin.stowOpenHere ? 250 : 180
                        easing.type: barWin.stowOpenHere ? Easing.OutCubic : Easing.InCubic
                    }
                }
                width: barWin.barVertical ? 56 : parent.width
                height: barWin.barVertical ? parent.height : 42
                clip: true
                visible: barWin.drawerVisible
                z: 1

                Rectangle {
                    anchors.fill: parent
                    color: barTheme.bg
                }
                Row {
                    id: stowRow
                    // 整排水平居中：排宽小于条宽时居中；排宽超出条宽时
                    // 回落 x:4 左对齐，避免两边同时裁切。implicitWidth
                    // 随槽宽动画连续变化，居中位置跟着平滑走。
                    x: stowRow.implicitWidth < stowStrip.width ? (stowStrip.width - stowRow.implicitWidth) / 2 : 4
                    y: 4
                    spacing: 2
                    height: 32
                    visible: !barWin.barVertical
                    Repeater {
                        model: (!barWin.barVertical && barInst.toolsGroupRef && barInst.toolsGroupRef.zoneReady) ? barInst.toolsGroupRef.stowLayout : []
                        delegate: barInst.toolsGroupRef ? barInst.toolsGroupRef.stowDelegateRef : null
                    }
                    Repeater {
                        model: !barWin.barVertical && barInst.zoneReady ? barInst.stowLayout : []
                        delegate: barInst.stowDelegateRef
                    }
                    Repeater {
                        model: barWin.barVertical ? [] : barInst.blockOrder
                        delegate: barInst.blockHolderDelegateRef
                    }
                }
                // 竖条抽屉上下分区：与栏本体对偶——左区收纳（工具组）+ 左侧整块
                // （启动器/工作区/音乐）贴顶，右区收纳 + 托盘整块贴底，中间弹性空隙；
                // 横向 Row 不动
                Item {
                    id: stowCol
                    anchors.fill: parent
                    visible: barWin.barVertical
                    Column {
                        anchors { top: parent.top; horizontalCenter: parent.horizontalCenter }
                        spacing: 2
                        Repeater {
                            model: (barWin.barVertical && barInst.toolsGroupRef && barInst.toolsGroupRef.zoneReady) ? barInst.toolsGroupRef.stowLayout : []
                            delegate: barInst.toolsGroupRef ? barInst.toolsGroupRef.stowDelegateRef : null
                        }
                        Repeater {
                            model: barWin.barVertical ? barInst.blockOrder.slice(0, 3) : []
                            delegate: barInst.blockHolderDelegateRef
                        }
                    }
                    Column {
                        anchors { bottom: parent.bottom; horizontalCenter: parent.horizontalCenter }
                        spacing: 2
                        Repeater {
                            model: barWin.barVertical && barInst.zoneReady ? barInst.stowLayout : []
                            delegate: barInst.stowDelegateRef
                        }
                        Repeater {
                            model: barWin.barVertical ? barInst.blockOrder.slice(3) : []
                            delegate: barInst.blockHolderDelegateRef
                        }
                    }
                }
            }
        }
    }

    // 胶囊拖拽幽灵覆盖窗（Overlay 层全宽透明窗）：只在本屏拖拽进行时可见，
    // 幽灵画在栏窗口之上，不被栏的裁剪/布局约束。mask 空 Region = 输入全穿透，
    // 拖拽事件仍由栏内 pill 的 MouseArea 独占。坐标与栏窗口同原点
    // （同屏、同顶边、同左锚定、margins 0）；高度 160 容许指针拖出栏下沿。
    // bottom 时窗底锚定、窗高仍 160：栏窗拖拽中恒为 94 高（三种拖拽起拖
    // 都开抽屉），纵坐标换算固定 +（160-winHHere），winHHere 由
    // stowOpen/stowScreen live 判定（拖拽屏恒为 94，换算恒成立）。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            id: ghostWin
            required property var modelData
            screen: modelData
            visible: Comp.UiState.dragActive && Comp.UiState.dragScreen === modelData.name

            property bool isBottom: Comp.UiState.barDirection === "bottom"
            property bool isVertical: Comp.UiState.barDirection === "left" || Comp.UiState.barDirection === "right"
            property bool isRight: Comp.UiState.barDirection === "right"
            property int winHHere: (Comp.UiState.stowOpen && Comp.UiState.stowScreen === modelData.name) ? 94 : 46
            property int winWHere: (Comp.UiState.stowOpen && Comp.UiState.stowScreen === modelData.name) ? (isVertical ? 118 : 94) : (isVertical ? 56 : 46)
            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection !== "top"; left: Comp.UiState.barDirection !== "right"; right: Comp.UiState.barDirection !== "left" }
            margins { top: 0; left: 0; right: 0; bottom: 0 }
            implicitWidth: 160
            implicitHeight: 160
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            exclusiveZone: -1
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { }

            Rectangle {
                width: Comp.UiState.dragW
                height: Comp.UiState.dragH
                radius: 10
                opacity: 0.92
                color: Comp.UiState.dragBg
                x: (ghostWin.isRight ? Comp.UiState.dragX + (160 - ghostWin.winWHere) : Comp.UiState.dragX) - width / 2
                y: (ghostWin.isBottom ? Comp.UiState.dragY + (160 - ghostWin.winHHere) : Comp.UiState.dragY) - height / 2
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

    // 搬家停靠预览（Overlay 全屏透明窗）：只在搬家进行中显示于被拖屏，
    // 四边各一矩形（顶/底全宽 46 高、左/右全高 56 宽），仅指针最近边
    // 半透明显示；mask 空 Region = 输入全穿透，不干扰栏内手势抓取。
    // 停靠与方向切换走同一 UiState.barDirection（松手时 setBarDirection）。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            visible: Comp.UiState.moveActive && modelData.name === Comp.UiState.moveScreen

            Theme { id: moveTheme }

            anchors { top: true; left: true; right: true; bottom: true }
            margins { top: 0; left: 0; right: 0; bottom: 0 }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
            mask: Region { }

            Rectangle {
                anchors { top: parent.top; left: parent.left; right: parent.right }
                height: 46
                visible: Comp.UiState.moveEdge === "top"
                color: Qt.alpha(moveTheme.accent, 0.18)
                border.color: moveTheme.accent
                border.width: 2
            }
            Rectangle {
                anchors { bottom: parent.bottom; left: parent.left; right: parent.right }
                height: 46
                visible: Comp.UiState.moveEdge === "bottom"
                color: Qt.alpha(moveTheme.accent, 0.18)
                border.color: moveTheme.accent
                border.width: 2
            }
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
                width: 56
                visible: Comp.UiState.moveEdge === "left"
                color: Qt.alpha(moveTheme.accent, 0.18)
                border.color: moveTheme.accent
                border.width: 2
            }
            Rectangle {
                anchors { top: parent.top; bottom: parent.bottom; right: parent.right }
                width: 56
                visible: Comp.UiState.moveEdge === "right"
                color: Qt.alpha(moveTheme.accent, 0.18)
                border.color: moveTheme.accent
                border.width: 2
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; left: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 42; bottom: Comp.UiState.barDirection === "bottom" ? 42 : 0; left: Math.max(0, ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.media.anchor] || {})[modelData.name] || 0) - 95) }
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; left: true }
            // 居中锚定 + 屏幕边缘钳制：左侧收起后 pill 左移，anchor-w/2 会成负数；
            // modelData.width 兜底 99999（取不到时退化为只钳左缘，原行为不变）
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 52; bottom: Comp.UiState.barDirection === "bottom" ? 52 : 0; left: Math.max(0, Math.min(((Comp.UiState.anchorMap[Comp.UiState.popupGeom.viz.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.viz.w / 2, (modelData.width || 99999) - Comp.UiState.popupGeom.viz.w)) }
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; left: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 52; bottom: Comp.UiState.barDirection === "bottom" ? 52 : 0; left: Math.max(0, ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.vol.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.vol.w / 2) }
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; right: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 52; bottom: Comp.UiState.barDirection === "bottom" ? 52 : 0; right: 12 }
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; left: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 52; bottom: Comp.UiState.barDirection === "bottom" ? 52 : 0; left: Math.max(0, (Comp.UiState.notifSnap[modelData.name] || 0) - 210) }
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; left: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 52; bottom: Comp.UiState.barDirection === "bottom" ? 52 : 0; left: Math.max(0, ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.bri.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.bri.w / 2) }
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

            anchors { top: Comp.UiState.barDirection !== "bottom"; bottom: Comp.UiState.barDirection === "bottom"; left: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : 52; bottom: Comp.UiState.barDirection === "bottom" ? 52 : 0; left: Math.max(0, Math.min(((Comp.UiState.anchorMap[Comp.UiState.popupGeom.cc.anchor] || {})[modelData.name] || 0) - Comp.UiState.popupGeom.cc.w / 2, (modelData.width || 99999) - Comp.UiState.popupGeom.cc.w)) }
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

    // 天气面板 overlay（全屏窗承载：背景点外关闭 + Esc，与边栏同款；
    // 卡片锚在天气胶囊下方，动画在 PopupReveal，内容在 WeatherPanel）。
    // 定位的唯一方向参数是 popupDir（当前 bar 在顶部 → "down"）：
    // 夹取只沿 bar 长轴推导，生长原点始终跟胶囊投影、与面板位置解耦。
    Variants {
        model: Quickshell.screens
        PanelWindow {
            required property var modelData
            screen: modelData
            // visible = 打开中 || 还在播退出动画（PopupReveal.presented），退出播完才真隐藏
            visible: (Comp.UiState.weatherOpen || weatherReveal.presented) && modelData.name === Comp.UiState.weatherScreen

            Theme { id: weatherTheme }

            property string popupDir: Comp.UiState.panelDir
            // 锚点与几何走 UiState 登记（直接下标读 anchorMap，见 UiState 注释）
            property real anchorX: ((Comp.UiState.anchorMap[Comp.UiState.popupGeom.weather.anchor] || {})[modelData.name] || 0)
            property real anchorY: ((Comp.UiState.anchorMapY[Comp.UiState.popupGeom.weather.anchor] || {})[modelData.name] || 0)
            property real panelW: Comp.UiState.popupGeom.weather.w
            // 夹取：优先居中对齐胶囊，出界往回平移到离所在屏边缘 8px
            property real panelX: Math.max(8, Math.min(anchorX - panelW / 2, (modelData.width || 99999) - panelW - 8))
            // 竖条：沿长轴（y）夹取，面板贴栏向屏内水平展开（窗原点已在栏+缝外）
            property real panelY: Math.max(8, Math.min(anchorY - weatherReveal.height / 2, (modelData.height || 99999) - weatherReveal.height - 8))
            property bool openHere: Comp.UiState.weatherOpen && modelData.name === Comp.UiState.weatherScreen
            onOpenHereChanged: { if (openHere) weatherPanel.reload(); }

            anchors { top: true; left: true; right: true; bottom: true }
            // top 时窗顶留 46（不遮顶栏）；bottom 时窗底留 46（不遮底栏），
            // 面板贴栏向屏内展开（top 在栏下 6px、bottom 在栏上 6px）
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : (Comp.UiState.barDirection === "left" || Comp.UiState.barDirection === "right" ? 0 : 46); left: Comp.UiState.barDirection === "left" ? 62 : 0; right: Comp.UiState.barDirection === "right" ? 62 : 0; bottom: Comp.UiState.barDirection === "bottom" ? 46 : 0 }
            color: "transparent"
            exclusionMode: ExclusionMode.Ignore
            WlrLayershell.layer: WlrLayer.Overlay
            // 独占键盘以接 Esc（边栏同款），关面板即归还
            WlrLayershell.keyboardFocus: WlrKeyboardFocus.Exclusive

            // 背景：点面板外关闭（声明在卡片之前，卡片在上）
            MouseArea {
                anchors.fill: parent
                onClicked: Comp.UiState.weatherOpen = false
            }

            Item {
                id: weatherWrap
                x: Comp.UiState.barDirection === "left" ? 0 : Comp.UiState.barDirection === "right" ? (modelData.width || 99999) - 62 - panelW : panelX
                y: (Comp.UiState.barDirection === "left" || Comp.UiState.barDirection === "right") ? panelY : (Comp.UiState.barDirection === "bottom" ? (modelData.height || 600) - 46 - 6 - weatherReveal.height : 6)
                width: panelW
                height: weatherReveal.height
                focus: true
                Keys.onEscapePressed: Comp.UiState.weatherOpen = false

                Comp.PopupReveal {
                    id: weatherReveal
                    width: panelW
                    height: weatherPanel.implicitHeight
                    shown: Comp.UiState.weatherOpen && modelData.name === Comp.UiState.weatherScreen
                    direction: popupDir
                    originX: anchorX - panelX
                    originY: anchorY - panelY

                    Comp.WeatherPanel {
                        id: weatherPanel
                        theme: weatherTheme
                        width: panelW
                    }
                }
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

            // 全屏（留 46 不遮栏）：top 时顶留 46、bottom 时底留 46；竖条时顶/底不留（无顶/底栏可避）
            anchors { top: true; left: true; right: true; bottom: true }
            margins { top: Comp.UiState.barDirection === "bottom" ? 0 : (Comp.UiState.barDirection === "left" || Comp.UiState.barDirection === "right" ? 0 : 46); left: 0; right: 0; bottom: Comp.UiState.barDirection === "bottom" ? 46 : 0 }
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
            // visible = 打开中 || picker 还在播退出动画（presented）：退出播完才真正隐藏
            visible: (Comp.UiState.wallpaperPickerOpen || pickerItem.presented) && modelData.name === Comp.UiState.wallpaperPickerScreen

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
                id: pickerItem
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
