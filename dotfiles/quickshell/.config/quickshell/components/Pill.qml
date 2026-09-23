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

    // overlay 锚点上报：设 anchorKey（如 "volAnchorX"）后，
    // pill 中心横坐标实时写入 UiState，同名 overlay 卡片锚定到其下方。
    // 为空则关闭上报，零开销。
    property string anchorKey: ""
    // 所在屏名：双屏下两边 pill 同时上报，UiState 按屏分键存放，
    // overlay 只取自己屏的值，互不覆盖。
    property string anchorScreen: ""
    function updateAnchor() {
        if (anchorKey === "" || width <= 0)
            return;
        // 顶层 parent 即本窗 contentItem：顶栏窗全宽贴屏无边距，
        // 相对它的横坐标就是输出坐标。禁止 mapToItem(null)——
        // 本 Qt 版本传 null 近似返回原点，锚点恒 ~20，浮窗全飞左缘。
        var top = root;
        try {
            while (top.parent)
                top = top.parent;
        } catch (e) {
            return;
        }
        var p = root.mapToItem(top, width / 2, 0);
        if (p)
            UiState.setAnchor(anchorKey, anchorScreen, p.x);
    }
    onXChanged: updateAnchor()
    onWidthChanged: updateAnchor()
    Component.onCompleted: { updateAnchor(); root.armReveal(); }
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
    property bool shown: pillText !== "" && !forceHidden
    property bool forceHidden: false
    // 依次出场：按兄弟顺序排号，一格 90ms，从左往右一个一个冒出来。
    // 用序号不用 x——收起时全挤在左边，x 全约等于 0 排不出顺位。
    // 首格约 0.1s 即现（跟手），整栏约 2 秒走完；数据没到的 shown 为 false
    // 自然排后面。出场只走一次，文本更新不重排。
    property bool revealed: false
    function siblingIndex() {
        try {
            var kids = parent ? parent.children : null;
            if (!kids)
                return 0;
            for (var i = 0; i < kids.length; i++) {
                if (kids[i] === root)
                    return i;
            }
        } catch (e) {}
        return 0;
    }
    function armReveal() {
        if (root.revealed || !root.shown)
            return;
        revealTimer.interval = root.siblingIndex() * 55;
        revealTimer.restart();
    }
    Timer {
        id: revealTimer
        repeat: false
        onTriggered: root.revealed = true
    }
    onShownChanged: {
        if (root.shown)
            root.armReveal();
        else
            root.revealed = false;
    }
    // 固定宽度（>0 生效）：内容变化不改尺寸，锚定它的浮窗就不会跳。
    // 给铃铛这种计数忽有忽无的用。
    property real fixedWidth: 0
    property real contentW: fixedWidth > 0 ? fixedWidth : label.implicitWidth + 20
    property real animW: (shown && revealed) ? contentW : 0
    // 启动门控：加载期直接到位，门开后才播动画（见 UiState.animReady）。
    // 收展跟手：OutCubic 起步快落地柔，宽 300ms + 透明 200ms，
    // 全组同一起点同节奏，自然齐出齐收
    Behavior on animW { enabled: UiState.animReady; NumberAnimation { duration: 300; easing.type: Easing.OutCubic } }
    Behavior on opacity { enabled: UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.OutCubic } }

    visible: opacity > 0.01
    opacity: (shown && revealed) ? 1 : 0
    height: 32
    width: contentW
    Layout.preferredWidth: animW
    Layout.preferredHeight: 32
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
    color: mouse.containsMouse ? normalFg : normalBg
    Behavior on color {
        SequentialAnimation {
            PauseAnimation { duration: transDelay }
            ColorAnimation { duration: transDur; easing.type: Easing.InOutQuad }
        }
    }

    Text {
        id: label
        anchors.centerIn: parent
        text: root.pillText
        font.family: root.fontFamily
        font.pixelSize: root.textSize
        font.bold: root.bold
        color: mouse.containsMouse ? root.normalBg : root.normalFg
        Behavior on color {
            SequentialAnimation {
                PauseAnimation { duration: root.transDelay }
                ColorAnimation { duration: root.transDur; easing.type: Easing.InOutQuad }
            }
        }
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
        // 即时按压反馈：状态落地要 0.5 秒（补刷+聚合），先缩一下证明点到了；
        // scale 不触发布局，无抖动；常开（含加载期）
        onPressed: root.scale = 0.93
        onReleased: root.scale = 1
        onCanceled: root.scale = 1
        onClicked: mouseEvent => {
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
