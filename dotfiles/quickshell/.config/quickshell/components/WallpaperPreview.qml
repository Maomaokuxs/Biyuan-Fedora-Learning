// WallpaperPreview.qml — 壁纸大预览组件（UI 与动效隔离）
//
// 对外 API：
//   property url source              当前显示的壁纸（组件内部维护，显示完成后更新）
//   property color bgColor            图片加载前的底色
//   readonly property bool animating  是否正在播过渡动画
//   function show(url, animated=true) 显示新壁纸；animated=false 或动画进行中则直接硬切
//   function setDirect(url)           直接设置（打开选择器初次显示，无动画）
//
// 动效（2026-10-22 按 mock 定稿）：切图只做 180ms 交叉淡化——新图叠在旧图上淡入，
// 无位移、无缩放、无裁剪。图是内容，不跟窗口动效逻辑走。
// 新图 Ready 才开播（避免异步未加载时纹理为空、动画白跑），超时 800ms 直接显示。
import QtQuick
import Quickshell.Widgets

Item {
    id: root

    property url source: ""
    property color bgColor: "transparent"
    readonly property bool animating: fadeAnim.running

    // 待显示的 url（等前图 Ready）
    property string pendingUrl: ""

    function show(url, animated) {
        var u = String(url || "");
        if (u === "" || u === String(root.source)) return;
        if (animated === undefined) animated = true;
        // 硬切：不播动画，或上一次淡化还在播（避免 restart 把动画打回起点导致永远播不完）
        if (!animated || fadeAnim.running) {
            fadeAnim.stop();
            fallbackTimer.stop();
            pendingUrl = "";
            frontImg.opacity = 0;
            frontImg.source = "";
            root.source = u;
            return;
        }
        // 交叉淡化：等前图 Ready 再开播
        pendingUrl = u;
        fallbackTimer.restart();
        frontImg.source = u;
        if (frontImg.status === Image.Ready && String(frontImg.source) === u) {
            pendingUrl = "";
            fallbackTimer.stop();
            fadeAnim.restart();
        }
        // 否则等 onStatusChanged
    }

    // 直接设置（打开选择器初次显示，无动画）
    function setDirect(url) {
        var u = String(url || "");
        fadeAnim.stop();
        fallbackTimer.stop();
        pendingUrl = "";
        frontImg.opacity = 0;
        frontImg.source = "";
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

        // 前层：新图（交叉淡化，加载完成才淡入）
        Image {
            id: frontImg
            anchors.fill: parent
            source: ""
            opacity: 0
            sourceSize.width: 1280
            asynchronous: true; cache: true; smooth: true; mipmap: true
            fillMode: Image.PreserveAspectCrop
            onStatusChanged: {
                if (status === Image.Ready && root.pendingUrl !== ""
                        && String(source) === root.pendingUrl) {
                    root.pendingUrl = "";
                    fallbackTimer.stop();
                    fadeAnim.restart();
                } else if (status === Image.Error && root.pendingUrl !== "") {
                    // 加载失败：硬切
                    root.pendingUrl = "";
                    fallbackTimer.stop();
                    fadeAnim.stop();
                    frontImg.opacity = 0;
                    root.source = source;
                    frontImg.source = "";
                }
            }
        }
    }

    NumberAnimation {
        id: fadeAnim
        target: frontImg
        property: "opacity"
        from: 0
        to: 1
        duration: 180
        easing.type: Easing.OutCubic
        onFinished: {
            root.source = frontImg.source;
            frontImg.opacity = 0;
            frontImg.source = "";
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
                fadeAnim.stop();
                frontImg.opacity = 0;
                root.source = frontImg.source;
                frontImg.source = "";
            }
        }
    }
}
