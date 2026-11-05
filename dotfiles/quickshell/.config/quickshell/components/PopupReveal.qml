import QtQuick

// 锚点弹窗动画壳（UI/动画分离：内容组件只管排版，动画全在这里）。
// 从锚点（胶囊中心在壳坐标系内的投影）以缩放 + 淡入 + 小位移长出
// （入场约 280ms OutCubic），退出更快、原路收回（约 170ms InCubic）。
//
// direction 是唯一的方向参数（默认 "down"：bar 在顶部、向下弹）：
// 位移轴与缩放原点全部由它推导，宿主不要再散写方向逻辑。bar 将来换边时
// 只改传入值：
//   down  原点在顶边（originX 投影），入场从上方 10px 落下
//   up    原点在底边（originX 投影），入场从下方 10px 升起
//   right 原点在左边（originY 投影），入场从左方 10px 推入
//   left  原点在右边（originY 投影），入场从右方 10px 推入
Item {
    id: root
    default property alias content: box.data

    property bool shown: false
    property string direction: "down"
    // 锚点投影：down/up 用 originX，left/right 用 originY
    property real originX: width / 2
    property real originY: height / 2
    // presented：入场一开始即 true，退出动画播完才 false；
    // 宿主窗口的 visible 要绑它（open || presented），否则退出会被硬切。
    property bool presented: false

    // 动画状态量（收起态：透明、缩到 0.92、沿方向轴偏 10px）
    property real aOpacity: 0
    property real aScale: 0.92
    property real aOff: 10

    readonly property real originXv: direction === "right" ? 0 : (direction === "left" ? width : originX)
    readonly property real originYv: direction === "down" ? 0 : (direction === "up" ? height : originY)
    readonly property real offX: direction === "right" ? -aOff : (direction === "left" ? aOff : 0)
    readonly property real offY: direction === "down" ? -aOff : (direction === "up" ? aOff : 0)

    visible: presented

    onShownChanged: {
        if (shown) {
            presented = true;
            exitAnim.stop();
            enterAnim.restart();
        } else if (presented) {
            enterAnim.stop();
            exitAnim.restart();
        }
    }
    Component.onCompleted: {
        // 启动即打开态（重启时面板本就开着）：直接到位，不播入场
        if (shown) {
            presented = true;
            aOpacity = 1;
            aScale = 1;
            aOff = 0;
        }
    }

    ParallelAnimation {
        id: enterAnim
        NumberAnimation { target: root; property: "aOpacity"; to: 1; duration: 280; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "aScale"; to: 1; duration: 280; easing.type: Easing.OutCubic }
        NumberAnimation { target: root; property: "aOff"; to: 0; duration: 280; easing.type: Easing.OutCubic }
    }
    ParallelAnimation {
        id: exitAnim
        NumberAnimation { target: root; property: "aOpacity"; to: 0; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "aScale"; to: 0.92; duration: 170; easing.type: Easing.InCubic }
        NumberAnimation { target: root; property: "aOff"; to: 10; duration: 170; easing.type: Easing.InCubic }
        onStopped: { if (!root.shown) root.presented = false; }
    }

    Item {
        id: box
        anchors.fill: parent
        opacity: root.aOpacity
        transform: [
            Scale {
                origin.x: root.originXv
                origin.y: root.originYv
                xScale: root.aScale
                yScale: root.aScale
            },
            Translate { x: root.offX; y: root.offY }
        ]
    }
}
