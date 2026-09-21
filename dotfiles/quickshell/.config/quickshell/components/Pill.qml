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
        var p = mapToItem(null, width / 2, 0);
        if (p)
            UiState.setAnchor(anchorKey, anchorScreen, p.x);
    }
    onXChanged: updateAnchor()
    onWidthChanged: updateAnchor()
    Component.onCompleted: updateAnchor()
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
    // forceHidden：外部开关（显隐 flag）直控显隐，不等轮询回执，
    // 使一组模块同起同落、单段动画。
    property bool shown: pillText !== "" && !forceHidden
    property bool forceHidden: false
    // 固定宽度（>0 生效）：内容变化不改尺寸，锚定它的浮窗就不会跳。
    // 给铃铛这种计数忽有忽无的用。
    property real fixedWidth: 0
    property real contentW: fixedWidth > 0 ? fixedWidth : label.implicitWidth + 20
    property real animW: shown ? contentW : 0
    // 启动门控：加载期直接到位，门开后才播动画（见 UiState.animReady）
    Behavior on animW { enabled: UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
    Behavior on opacity { enabled: UiState.animReady; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

    visible: opacity > 0.01
    opacity: shown ? 1 : 0
    height: 32
    width: contentW
    Layout.preferredWidth: animW
    Layout.preferredHeight: 32
    radius: 10
    clip: true
    color: mouse.containsMouse ? normalFg : normalBg

    Text {
        id: label
        anchors.centerIn: parent
        text: root.pillText
        font.family: root.fontFamily
        font.pixelSize: root.textSize
        font.bold: root.bold
        color: mouse.containsMouse ? root.normalBg : root.normalFg
    }

    MouseArea {
        id: mouse
        anchors.fill: parent
        hoverEnabled: true
        acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
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
