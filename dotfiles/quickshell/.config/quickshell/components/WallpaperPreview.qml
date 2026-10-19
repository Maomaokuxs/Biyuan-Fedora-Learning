// WallpaperPreview.qml — 壁纸大预览组件（UI 与动效隔离）
//
// 对外 API：
//   property url source              当前显示的壁纸（组件内部维护，显示完成后更新）
//   property color bgColor            图片加载前的底色
//   readonly property bool animating  是否正在播过渡动画
//   function show(url, animated=true) 显示新壁纸；animated=false 或动画进行中则直接硬切
//
// 动效：左→右裁剪揭示。实现原理：新图放在 clip 容器里固定全尺寸，
// 容器宽度 0→满播 500ms OutCubic，只做揭示，图片本身不动。
// 不用 Canvas/ShaerEffect，从原理上杜绝缩放/拉伸问题。
import QtQuick
import Quickshell.Widgets

Item {
    id: root

    property url source: ""
    property color bgColor: "transparent"
    readonly property bool animating: revealAnim.running

    // 待显示的 url（等前图 Ready）
    property string pendingUrl: ""

    function show(url, animated) {
        var u = String(url || "");
        if (u === "" || u === String(root.source)) return;
        if (animated === undefined) animated = true;
        // 硬切：不播动画，或上一次揭示还在播（避免 restart 把动画打回起点导致永远播不完）
        if (!animated || revealAnim.running) {
            revealAnim.stop();
            fallbackTimer.stop();
            pendingUrl = "";
            revealBox.width = 0;
            root.source = u;
            return;
        }
        // 动画揭示：等前图 Ready 再开播
        pendingUrl = u;
        fallbackTimer.restart();
        frontImg.source = u;
        if (frontImg.status === Image.Ready && String(frontImg.source) === u) {
            pendingUrl = "";
            fallbackTimer.stop();
            revealBox.width = 0;
            revealAnim.restart();
        }
        // 否则等 onStatusChanged
    }

    // 直接设置（打开选择器初次显示，无动画）
    function setDirect(url) {
        var u = String(url || "");
        revealAnim.stop();
        fallbackTimer.stop();
        pendingUrl = "";
        revealBox.width = 0;
        root.source = u;
    }

    ClippingRectangle {
        anchors.fill: parent
        radius: 12
        color: root.bgColor

        // 底层：当前图（静态）
        Image {
            id: backImg
            anchors.fill: parent
            source: root.source
            sourceSize.width: 1280 // 仅限宽，高按比例自适应，避免 9K 直解
            asynchronous: true; cache: true; smooth: true; mipmap: true
            fillMode: Image.PreserveAspectCrop
        }

        // 前层：新图（裁剪揭示）
        Item {
            id: revealBox
            anchors { top: parent.top; bottom: parent.bottom; left: parent.left }
            width: 0
            clip: true
            visible: width > 0.5
            Image {
                id: frontImg
                // 固定为组件全尺寸，不随 revealBox 的宽度动画被挤压
                width: root.width
                height: root.height
                source: ""
                sourceSize.width: 1280
                asynchronous: true; cache: true; smooth: true; mipmap: true
                fillMode: Image.PreserveAspectCrop
                onStatusChanged: {
                    if (status === Image.Ready && root.pendingUrl !== ""
                            && String(source) === root.pendingUrl) {
                        root.pendingUrl = "";
                        fallbackTimer.stop();
                        revealBox.width = 0;
                        revealAnim.restart();
                    } else if (status === Image.Error && root.pendingUrl !== "") {
                        // 加载失败：硬切
                        root.pendingUrl = "";
                        fallbackTimer.stop();
                        revealAnim.stop();
                        revealBox.width = 0;
                        root.source = source;
                    }
                }
            }
        }
    }

    NumberAnimation {
        id: revealAnim
        target: revealBox
        property: "width"
        from: 0
        to: root.width
        duration: 500
        easing.type: Easing.OutCubic
        onFinished: {
            root.source = frontImg.source;
            revealBox.width = 0;
        }
    }

    // 兜底：前图 800ms 还没 Ready，直接硬切
    Timer {
        id: fallbackTimer
        interval: 800
        repeat: false
        onTriggered: {
            if (root.pendingUrl !== "") {
                root.pendingUrl = "";
                revealAnim.stop();
                revealBox.width = 0;
                root.source = frontImg.source;
            }
        }
    }
}
