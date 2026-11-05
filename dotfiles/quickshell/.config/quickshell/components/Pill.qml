import QtQuick
import QtQuick.Layouts

// 通用色块：对齐 waybar 32px悬浮圆角块 (min-height 28, radius 9, padding 0 10)
Rectangle {
    id: root
    property string pillText: ""
    property int textSize: 14
    property bool bold: false
    property string normalBg: "#998c8c"  // FALLBACK: Bar 必传 baseBg/normalBg，此值走不到
    property string normalFg: "#6a442f"  // FALLBACK: Bar 必传 baseFg/normalFg，此值走不到
    property string fontFamily: "JetBrainsMono Nerd Font"
    property string clickLeft: ""
    property string clickRight: ""
    property string clickMiddle: ""
    property string scrollUpCmd: ""
    property string scrollDownCmd: ""
    property string tipText: ""

    signal leftClicked
    signal rightClicked
    signal middleClicked
    signal scrollUp
    signal scrollDown

    // ---- 拖拽组合（顶栏胶囊区专用，dragEnabled=false 时零影响）----
    property string pillId: ""
    // bare：组内成员模式，不画自己的底，只画内容；底色由组容器统一画
    property bool bare: false
    property color bareFg: normalFg
    property bool dragEnabled: false
    // 冻结：已收纳且抽屉关闭时由区控制器置 true。ScriptPill 据此停轮询；
    // 普通 Pill 无消费者，置位无副作用。
    property bool frozen: false
    // ---- 抽屉模式：胶囊被抽屉槽领养时由 delegate 置 true，显示
    // 「图标 + 中文名」、不显示实时数值；bar 槽领养时置 false，
    // 渲染与改前一字不动。图标取 pillText 首个码点（ASCII 字母/
    // 数字或 CJK 开头视为无图标，走 UiState 兜底图标表，如时钟的
    // hh:mm、输入法的「中」/「EN」是状态值不是图标）。注意：图标
    // 提取必须内联写在绑定里——本构建的绑定不追踪方法内部的
    // 属性读取（UiState 注释有言在先），经方法读 pillText 会只
    // 求值一次、天气图标换天也不会跟；drawerName/drawerIcon
    // 是 id 的纯函数（只读字面量表），经方法调无妨。
    property bool drawerMode: false
    // ---- 代理对感知取首字符：本构建 Array.from 按 UTF-16 码元切分
    // （探针实测 Array.from("\u{F0209}").length === 2），增补平面
    // 图标会被拆成高/低代理孤元、渲染成两个问号菱形；图标提取
    // 一律禁用 Array.from，改 charCodeAt 判高代理 + substring 取整对。
    // 纯字符串函数（只用参数、不读响应式属性），绑定里传参调用可追踪。
    function firstChar(t) {
        if (t.length === 0)
            return "";
        var c = t.charCodeAt(0);
        if (c >= 0xD800 && c <= 0xDBFF && t.length > 1 && t.charCodeAt(1) >= 0xDC00 && t.charCodeAt(1) <= 0xDFFF)
            return t.substring(0, 2);
        return t.charAt(0);
    }
    function restChars(t) {
        var f = root.firstChar(t);
        return f.length >= t.length ? "" : t.substring(f.length);
    }
    function isIconChar(c) {
        if (c === "")
            return false;
        if (/[A-Za-z0-9]/.test(c))
            return false;
        var cp = c.codePointAt(0);
        return cp < 0x4E00 || cp > 0x9FFF;
    }
    property string drawerLabel: {
        if (!root.drawerMode)
            return "";
        var name = UiState.drawerName(root.pillId);
        var icon = "";
        var t = root.pillText;
        if (t.length > 0) {
            var first = root.firstChar(t);
            if (root.isIconChar(first))
                icon = first;
        }
        if (icon === "")
            icon = UiState.drawerIcon(root.pillId);
        return icon === "" ? name : icon + " " + name;
    }
    // ---- 竖条模式：图标在上、文字在下一行完整显示（领养方按竖条方向置 vertical）----
    // 图标提取与抽屉模式同规则（首码点非 ASCII/数字/CJK 视为图标，取不到
    // 走 UiState 兜底图标表）；文字单行（见 vValue），过长单行截断。
    signal dragStarted(string id)
    property bool vertical: false
    // 工具条专用紧凑竖贴：左区工具 pill 被 ToolsGroup 领养时置 true，
    // 竖条 contentH 边距由 +6 收成 +2（图标间只剩 2px，仍可点）；归还/
    // 营救时复位 false，与 drawerMode/vertical 同一套领养开关
    property bool vCompact: false
    property string vIcon: {
        var t = root.pillText;
        var icon = "";
        if (t.length > 0) {
            var first = root.firstChar(t);
            if (root.isIconChar(first))
                icon = first;
        }
        if (icon === "")
            icon = UiState.drawerIcon(root.pillId);
        return icon;
    }
    // 竖条值行（单行）：抽屉模式是中文名全文；时钟是 "11:40" 全文；
    // 其余是实时值去图标后全文（"19°C"、"40%" 不再拆行）。过长由
    // vValueText 单行截断（elide）。
    property string vValue: {
        if (root.drawerMode)
            return UiState.drawerName(root.pillId);
        if (root.pillId === "clock")
            return root.pillText;
        var t = root.pillText;
        if (t.length === 0)
            return "";
        var f = root.firstChar(t);
        return root.isIconChar(f) ? root.restChars(t).trim() : t;
    }
    signal dragMoved(real wx, real wy)
    signal dragEnded()
    property bool dragging: false
    property bool suppressClick: false
    property point pressPt: Qt.point(0, 0)
    property int pressButton: 0

    // ---- 整组拖拽（长按抓组）：左键按住约 280ms 且单颗拖未起时发 pressHeld，
    // 控制器判定源槽成员 ≥2 才回调用 beginGroupDrag() 接管本次按压：此后移动/
    // 松手走 group* 信号，不触发单颗拖拽与点击。控制器不接管（单颗槽）时
    // 本组件无任何状态变化，后续移动照常起单颗拖、松手照常点击。
    // dragEnabled=false 时计时器不启动、信号永不发出，零影响。
    signal pressHeld(var pill)
    signal groupDragMoved(real wx, real wy)
    signal groupDragEnded()
    property bool groupDragging: false
    function beginGroupDrag() {
        if (root.dragging || root.groupDragging)
            return;
        root.groupDragging = true;
        root.scale = 1;
    }
    Timer {
        id: holdTimer
        interval: 280
        repeat: false
        onTriggered: {
            if (mouse.pressed && !root.dragging && root.pressButton === Qt.LeftButton)
                root.pressHeld(root);
        }
    }
    // 窗口坐标：逐级累加祖先 x/y。本 Qt 版本 mapToItem(null) 近似返回原点
    // （见下方 updateAnchor 注释），不能用；顶栏祖先链无旋转/缩放，累加等价。
    function absPos() {
        var x = 0, y = 0, n = root;
        var guard = 0;
        while (n && guard++ < 100) {
            x += n.x;
            y += n.y;
            n = n.parent;
        }
        return Qt.point(x, y);
    }

    // overlay 锚点上报：设 anchorKey（如 "volAnchorX"）后，
    // pill 中心横坐标实时写入 UiState，同名 overlay 卡片锚定到其下方。
    // 为空则关闭上报，零开销。
    property string anchorKey: ""
    // 所在屏名：双屏下两边 pill 同时上报，UiState 按屏分键存放，
    // overlay 只取自己屏的值，互不覆盖。
    property string anchorScreen: ""
    function updateAnchor() {
        // 隐藏 pill（forceHidden/空文本）不上报：它的 width 恒为 contentW，
        // 只靠 Layout.preferredWidth 压到 0，width 守卫拦不住，假锚点会把
        // 同 key 的弹窗拽到左缘（如 HDMI-A-1 的亮度卡）。shown 已含 forceHidden。
        if (anchorKey === "" || !root.shown)
            return;
        // 顶层 parent 即本窗 contentItem：顶栏窗全宽贴屏无边距，
        // 相对它的横坐标就是输出坐标。禁止 mapToItem(null)——
        // 本 Qt 版本传 null 近似返回原点，锚点恒 ~20，浮窗全飞左缘。
        var top = root;
        try {
            var guard2 = 0;
            while (top.parent && guard2++ < 100)
                top = top.parent;
        } catch (e) {
            return;
        }
        var p = root.mapToItem(top, width / 2, height / 2);
        if (p) {
            UiState.setAnchor(anchorKey, anchorScreen, p.x);
            UiState.setAnchorY(anchorKey, anchorScreen, p.y);
        }
    }
    onXChanged: updateAnchor()
    onWidthChanged: updateAnchor()
    Component.onCompleted: { updateAnchor(); }
    // 静态 pill（铃铛这种宽度常年不变的）事件钩子只在启动瞬间触发，
    // 那时窗口未就绪，锚点恒为 0，卡片飞左缘。1 秒刷一次兜底，
    // mapToItem 纯坐标换算，开销忽略不计。
    Timer {
        interval: 1000
        running: anchorKey !== ""
        repeat: true
        onTriggered: updateAnchor()
    }

    // 显隐走宽度+透明度动画，避免 visible 硬切换的生硬感。
    // animW 是真实可动画属性，Layout 取它做布局宽度；直接 width 保留给非布局场景。
    // forceHidden：外部开关（显隐 flag）直控显隐，不等轮询回执。
    // 抽屉模式下显隐看抽屉标签（图标+中文名），不看实时文本——收纳的
    // 胶囊即使当下无实时值，在抽屉里也以名字示人；bar 模式看 pillText 不变。
    property bool shown: root.drawerMode ? (root.drawerLabel !== "" && !forceHidden) : (pillText !== "" && !forceHidden)
    property bool forceHidden: false
    // 固定宽度（>0 生效）：内容变化不改尺寸，锚定它的浮窗就不会跳。
    // 给铃铛这种计数忽有忽无的用。抽屉模式下固定宽度不生效：抽屉标签
    // （图标+中文名）的宽度与实时文本无关，沿用会裁切或留空。
    property real fixedWidth: 0
    // 竖条方块贴与启动器徽标块同宽（UiState.tileW，Bar 按 launcherPill.width
    // 喂值，默认 35）；原 48 与托盘块对齐，块块宽窄不一。
    property real contentW: root.vertical ? UiState.tileW : ((fixedWidth > 0 && !root.drawerMode) ? fixedWidth : label.implicitWidth + (root.bare ? 8 : 20))
    property real contentH: root.vertical ? vCol.implicitHeight + (root.vCompact ? 2 : 6) : 32
    property real animW: shown ? contentW : 0
    property real animH: shown ? contentH : 0
    // 显隐动画：门控只管加载期，运行时交互保留收展动画
    Behavior on animW { enabled: UiState.animReady; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on animH { enabled: UiState.animReady; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on opacity { enabled: UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    height: root.vertical ? contentH : 32
    width: contentW
    Layout.preferredWidth: animW
    Layout.preferredHeight: root.vertical ? animH : 32
    radius: 10
    clip: true
    Behavior on scale { NumberAnimation { duration: 80; easing.type: Easing.OutQuad } }
    // 依次点亮：wave 按离中心距离排队从中间漫开，wipe 从左往右扫，
    // outside 从两边往中间收，twinkle 按位置哈希随机闪；
    // fade 均匀淡入；off 硬切。排队只在波形窗口期内生效，平时 hover 零延迟
    property string transStyle: UiState.transitionStyle
    property string transEff: transStyle === "random" ? UiState.transitionPick : transStyle
    property int transDur: transEff === "off" ? 0 : (transEff === "fade" ? 400 : 120)
    property int transDelay: {
        if (transEff === "fade" || transEff === "off" || Date.now() > UiState.waveUntil)
            return 0;
        var pw = parent ? parent.width : 0;
        if (pw <= 0)
            return 0;
        var cx = x + width / 2;
        if (transEff === "wipe")
            return Math.round(x * 0.5);
        if (transEff === "outside")
            return Math.round((pw / 2 - Math.abs(cx - pw / 2)) * 1.2);
        if (transEff === "twinkle")
            return Math.abs(Math.round((x * 2654435761) % 800));
        return Math.round(Math.abs(cx - pw / 2) * 1.2);
    }
    color: root.bare ? (mouse.containsMouse ? Qt.alpha(root.bareFg, 0.18) : "transparent") : (mouse.containsMouse ? normalFg : normalBg)
    Behavior on color {
        SequentialAnimation {
            PauseAnimation { duration: transDelay }
            ColorAnimation { duration: transDur; easing.type: Easing.InOutQuad }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        visible: !root.vertical
        text: root.drawerMode ? root.drawerLabel : root.pillText
        font.family: root.fontFamily
        font.pixelSize: root.textSize
        font.bold: root.bold
        color: root.bare ? root.bareFg : (mouse.containsMouse ? root.normalBg : root.normalFg)
        Behavior on color {
            SequentialAnimation {
                PauseAnimation { duration: root.transDelay }
                ColorAnimation { duration: root.transDur; easing.type: Easing.InOutQuad }
            }
        }
    }

    // 竖贴：图标在上、文字在下一行完整显示；值行单行，过长截断（elide）。
    // 值行字号 10：5 字 "11:40" 在 34.8 宽里放得下（11px 会顶满到截断）。
    Column {
        id: vCol
        anchors.centerIn: parent
        spacing: 1
        visible: root.vertical
        Text {
            id: vIconText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            text: root.vIcon
            font.family: root.fontFamily
            font.pixelSize: root.textSize
            font.bold: root.bold
            color: root.bare ? root.bareFg : (mouse.containsMouse ? root.normalBg : root.normalFg)
        }
        Text {
            id: vValueText
            anchors.horizontalCenter: parent.horizontalCenter
            visible: text !== ""
            width: UiState.tileW - 2
            text: root.vValue
            font.family: root.fontFamily
            font.pixelSize: 10
            font.bold: root.bold
            color: root.bare ? root.bareFg : (mouse.containsMouse ? root.normalBg : root.normalFg)
            horizontalAlignment: Text.AlignHCenter
            elide: Text.ElideRight
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        // 即时按压反馈：状态落地要 0.5 秒（补刷+聚合），先缩一下证明点到了；
        // scale 不触发布局，无抖动；常开（含加载期）
        onPressed: mouseEvent => {
            root.pressPt = Qt.point(mouseEvent.x, mouseEvent.y);
            root.pressButton = mouseEvent.button;
            if (root.dragEnabled && mouseEvent.button === Qt.LeftButton)
                holdTimer.restart();
            if (!root.dragging)
                root.scale = 0.93;
        }
        onPositionChanged: mouseEvent => {
            if (!root.dragEnabled || !pressed || root.pressButton !== Qt.LeftButton)
                return;
            if (root.groupDragging) {
                var gp = root.absPos();
                root.groupDragMoved(gp.x + mouseEvent.x, gp.y + mouseEvent.y);
                return;
            }
            if (!root.dragging) {
                var dx = mouseEvent.x - root.pressPt.x;
                var dy = mouseEvent.y - root.pressPt.y;
                if (Math.sqrt(dx * dx + dy * dy) <= 8)
                    return;
                holdTimer.stop();
                root.dragging = true;
                root.scale = 1;
                root.dragStarted(root.pillId);
            }
            var ap = root.absPos();
            root.dragMoved(ap.x + mouseEvent.x, ap.y + mouseEvent.y);
        }
        onReleased: {
            holdTimer.stop();
            root.scale = 1;
            if (root.groupDragging) {
                root.groupDragging = false;
                root.suppressClick = true;
                root.groupDragEnded();
            } else if (root.dragging) {
                root.dragging = false;
                root.suppressClick = true;
                root.dragEnded();
            }
        }
        onCanceled: {
            holdTimer.stop();
            root.scale = 1;
            if (root.groupDragging) {
                root.groupDragging = false;
                root.suppressClick = true;
                root.groupDragEnded();
            } else if (root.dragging) {
                root.dragging = false;
                root.suppressClick = true;
                root.dragEnded();
            }
        }
        onClicked: mouseEvent => {
            if (root.suppressClick) {
                root.suppressClick = false;
                return;
            }
            if (mouseEvent.button === Qt.LeftButton) {
                root.leftClicked();
                if (root.clickLeft !== "")
                    Exec.sh(root.clickLeft);
            } else if (mouseEvent.button === Qt.RightButton) {
                root.rightClicked();
                if (root.clickRight !== "")
                    Exec.sh(root.clickRight);
            } else {
                root.middleClicked();
                if (root.clickMiddle !== "")
                    Exec.sh(root.clickMiddle);
            }
        }
        onWheel: wheel => {
            var cmd = wheel.angleDelta.y > 0 ? root.scrollUpCmd : root.scrollDownCmd;
            if (wheel.angleDelta.y > 0)
                root.scrollUp();
            else
                root.scrollDown();
            if (cmd !== "")
                Exec.sh(cmd);
        }
    }
}
