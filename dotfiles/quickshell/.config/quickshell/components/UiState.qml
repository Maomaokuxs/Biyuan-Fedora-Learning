pragma Singleton

import QtQuick

// 跨窗口 UI 状态：Variants delegate 是隔离作用域，bar 里的点击
// 无法直接点亮 overlay 窗口，经此单例中转。
QtObject {
    id: root

    // 播放卡
    property bool mediaOpen: false
    property string mediaScreen: ""
    // 电平浮窗
    property bool vizOpen: false
    property string vizScreen: ""
    // 音量条
    property bool volOpen: false
    property string volScreen: ""
    // 亮度条
    property bool briOpen: false
    property string briScreen: ""
    property bool briExternal: false
    // 壁纸窗
    property bool wallOpen: false
    property string wallScreen: ""
    // 锚点按屏分键：双栏下两边 pill 同时上报，单全局值会被盖掉错乱。
    // 结构 {key: {screenName: x}}，整体重赋以触发绑定。
    property var anchorMap: ({})
    function setAnchor(key: string, screen: string, x: real): void {
        if (key === "" || screen === "")
            return;
        var m = Object.assign({}, root.anchorMap);
        var sub = Object.assign({}, m[key]);
        sub[screen] = x;
        m[key] = sub;
        root.anchorMap = m;
    }
    // 注意：不要在绑定里调方法读 anchorMap（如之前的 anchorFor），
    // 本 quickshell 版本绑定不追踪单例方法内部的属性读取，只求值一次。
    // 读端一律直接下标（直接读 anchorMap 才会被追踪）。
    // 弹窗几何注册表：调位置只改这里，不碰卡片样式。
    // anchor: anchorMap 的键；w: 卡片宽（居中即 锚点 - w/2）。
    // 注意：读端必须直接下标（见 anchorMap 注释），禁止包 anchorFor 方法。
    property var popupGeom: ({
        media: { anchor: "mediaAnchorX", w: 360 },
        viz: { anchor: "vizAnchorX", w: 400 },
        vol: { anchor: "volAnchorX", w: 280 },
        bri: { anchor: "briAnchorX", w: 280 },
        wall: { anchor: "wallAnchorX", w: 560 },
        notif: { w: 420 }
    })
    // 启动动画门：false 时所有 Pill 显隐直接到位（加载期数据陆续到达，
    // 若逐个播动画会稀稀拉拉）；true 后整栏淡入一次，此后交互动画正常播。
    // anomshell 等成品同样是整栏级过渡而非逐 pill 入场。
    property bool animReady: false
    // 换色波窗口：PaletteState 每次取到新配色就后延，波形期内色块按距离依次点亮，
    // 过期后 hover 等日常换色零延迟
    property double waveUntil: 0
    // 过渡风格：wave 追逐波 / fade 均匀淡入 / off 硬切 / random 随机抽取，
    // wipe 横扫 / outside 反波 / twinkle 闪烁（壁纸卡下拉框切换，落盘记忆）
    property string transitionStyle: "wave"
    // random 落点：每次新配色抽一次，非 random 模式不用它（读端自行判断）
    property string transitionPick: "wave"


    // 通知文本消毒：剥掉 ANSI/OSC 转义序列与控制字符。
    // 有些发送方（如 kwrited 转发的 wall 广播）会把终端调色序列塞进正文，
    // 在显示层统一洗，而不是去改每个发送方（更别说动 theme-sync）。
    function cleanText(s: string) {
        return String(s || "")
            .replace(/\x1B\][^\x07\x1B]*(?:\x07|\x1B\\)/g, "")
            .replace(/\x1B\[[0-9;?]*[A-Za-z]/g, "")
            .replace(/\x1B[()][0-9A-B]/g, "")
            .replace(/[^\x09\x0A\x0D\x20-\uFFFF]/g, "");
    }

    // overlay 卡片单开互斥：开任何一张，关其余；避免互相遮挡
    function closeOthers(except: string) {
        if (except !== "media")
            root.mediaOpen = false;
        if (except !== "viz")
            root.vizOpen = false;
        if (except !== "vol")
            root.volOpen = false;
        if (except !== "bri")
            root.briOpen = false;
        if (except !== "wall")
            root.wallOpen = false;
        if (except !== "notif")
            root.notifOpen = false;
    }

    function toggleNotif(screenName: string) {
        if (root.notifOpen && root.notifScreen === screenName)
            root.notifOpen = false;
        else {
            root.notifScreen = screenName;
            var s = Object.assign({}, root.notifSnap);
            // 直接下标（绑定外的一次性读取，不受追踪问题影响）
            s[screenName] = (root.anchorMap.notifAnchorX || {})[screenName] || 0;
            root.notifSnap = s;
            root.notifOpen = true;
            root.closeOthers("notif");
        }
    }

    function toggleMedia(screenName: string) {
        if (root.mediaOpen && root.mediaScreen === screenName)
            root.mediaOpen = false;
        else {
            root.mediaScreen = screenName;
            root.mediaOpen = true;
            root.closeOthers("media");
        }
    }

    function toggleViz(screenName: string) {
        if (root.vizOpen && root.vizScreen === screenName)
            root.vizOpen = false;
        else {
            root.vizScreen = screenName;
            root.vizOpen = true;
            root.closeOthers("viz");
        }
    }

    function toggleVol(screenName: string) {
        if (root.volOpen && root.volScreen === screenName)
            root.volOpen = false;
        else {
            root.volScreen = screenName;
            root.volOpen = true;
            root.closeOthers("vol");
        }
    }

    function toggleBri(screenName: string, external: bool) {
        if (root.briOpen && root.briScreen === screenName)
            root.briOpen = false;
        else {
            root.briScreen = screenName;
            root.briExternal = external;
            root.briOpen = true;
            root.closeOthers("bri");
        }
    }

    function toggleWall(screenName: string) {
        if (root.wallOpen && root.wallScreen === screenName)
            root.wallOpen = false;
        else {
            root.wallScreen = screenName;
            root.wallOpen = true;
            root.closeOthers("wall");
        }
    }

    // 通知中心
    property bool notifOpen: false
    property string notifScreen: ""
    // 中心浮窗用快照锚（按屏分键）：打开瞬间定死，之后清零计数导致 pill
    // 变窄也不跟跳
    property var notifSnap: ({})
}
