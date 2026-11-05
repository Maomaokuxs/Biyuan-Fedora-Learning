pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

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
    // 控制中心
    property bool ccOpen: false
    property string ccScreen: ""
    // 设置边栏（C 精修版，新增，不动原弹窗文件）：滑块 pill 左键走 sidebar，替换原控制中心入口
    property bool sidebarOpen: false
    property string sidebarScreen: ""
    property bool sidebarWallpaper: false
    // ZZZ 斜向壁纸选择器（独立窗口，居中 960×600）：Mod+Shift+W / 边栏壁纸行打开
    property bool wallpaperPickerOpen: false
    property string wallpaperPickerScreen: ""
    // 壁纸过渡（awww 真实类型），与 Pill 波形用的 transitionStyle 分开，落盘 ~/.cache/by-mgr/wallpaper-transition
    property string wallpaperTransition: "fade"
    // 锚点按屏分键：双栏下两边 pill 同时上报，单全局值会被盖掉错乱。
    // 结构 {key: {screenName: x}}，整体重赋以触发绑定。
    property var anchorMap: ({})
    function setAnchor(key: string, screen: string, x: real) {
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
    // 锚点 Y（竖条用）：结构与 anchorMap 同构 {key: {screenName: y}}，
    // Pill.updateAnchor 在上报 X 的同时上报胶囊中心 Y，竖条面板沿长轴夹取读它。
    property var anchorMapY: ({})
    function setAnchorY(key: string, screen: string, y: real) {
        if (key === "" || screen === "")
            return;
        var m = Object.assign({}, root.anchorMapY);
        var sub = Object.assign({}, m[key]);
        sub[screen] = y;
        m[key] = sub;
        root.anchorMapY = m;
    }
    // 抽屉模式中文名：胶囊 id → 中文名，未命中回落 id 本身。
    // （bar 模式不查这张表；drawerName/drawerIcon 是 id 的纯函数，
    // 只读字面量表、不读任何响应式属性，绑定调它们无妨。）
    function drawerName(id: string): string {
        var m = {
            "updates": "更新", "weather": "天气", "audio": "声音", "bri": "亮度",
            "cpu": "处理器", "pp": "性能", "mem": "内存", "net": "网络",
            "bt": "蓝牙", "bat": "电池", "clock": "时钟", "bell": "通知",
            "tray": "托盘", "fcitx": "输入法", "inhibit": "勿扰",
            "cc": "控制中心", "power": "电源",
            "pick": "取色", "clip": "剪贴板", "gamma": "夜灯",
            "theme": "主题", "wall": "壁纸", "screen": "屏幕",
            "rec": "录屏", "shot": "截图"
        };
        return m[id] !== undefined ? m[id] : id;
    }
    // 抽屉模式兜底图标：pillText 首码点不是图标时用。纯文字型
    // （时钟的 hh:mm）与状态值型（输入法的「中」/「EN」是状态
    // 不是图标）走这里；字形已过 fc-list 校验，确在
    // JetBrainsMono Nerd Font 内含（F017 时钟、F11C 键盘）。
    function drawerIcon(id: string): string {
        if (id === "clock")
            return "\uF017";
        if (id === "fcitx")
            return "\uF11C";
        return "";
    }
    // 弹窗几何注册表：调位置只改这里，不碰卡片样式。
    // anchor: anchorMap 的键；w: 卡片宽（居中即 锚点 - w/2）。
    // 注意：读端必须直接下标（见 anchorMap 注释），禁止包 anchorFor 方法。
    property var popupGeom: ({
        media: { anchor: "mediaAnchorX", w: 360 },
        viz: { anchor: "vizAnchorX", w: 480 },
        vol: { anchor: "volAnchorX", w: 280 },
        bri: { anchor: "briAnchorX", w: 280 },
        wall: { anchor: "wallAnchorX", w: 560 },
        cc: { anchor: "ccAnchorX", w: 460 },
        weather: { anchor: "weatherAnchorX", w: 372 },
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
    // 电平可视化效果：dance 律动 / spectrum 声谱 / off 基线
    // （电平浮窗切换，落盘记忆）
    property string vizEffect: "dance"
    // 音律自动关闭状态（LevelMeter 驱动，双屏实例幂等）：
    // 无音频 → vizEffect 切 "off"，用户选择暂存 vizEffectSaved，来声恢复；
    // VizCard 落盘读取/手动点选时看这个旗：自动关闭中只动暂存，手动点选直接清旗
    property string vizEffectSaved: ""
    property bool vizEffectAutoOff: false
    // 舞者编排：-1 自动（一次一式跟音乐换场），0-7 固定单式，8 混合（八式同放）；
    // VizCard 落盘记忆
    property int dancePattern: -1
    // random 落点：每次新配色抽一次，非 random 模式不用它（读端自行判断）
    property string transitionPick: "wave"

    // 胶囊拖拽幽灵（shell 层覆盖窗渲染）：起拖的 Bar 实例写、覆盖窗读。
    // dragX/dragY 是栏窗口坐标（覆盖窗与栏同屏同顶同左锚定，原点一致）。
    property bool dragActive: false
    property string dragScreen: ""
    property string dragText: ""
    property color dragBg: "transparent"
    property color dragFg: "#ffffff"
    property real dragX: 0
    property real dragY: 0
    property real dragW: 60
    property real dragH: 32

    // 收纳抽屉双模式：stowPersistent=false 是临时模式（任意区起拖时自动打开，
    // 落位后预约自动收起）；=true 是持久模式（在顶栏背景上向下拖打开、
    // 向上拖关闭，不自动收）。按屏分键（同 dragScreen 模式），
    // 另一屏的实例不跟着展开/解冻。
    property bool stowOpen: false
    property bool stowPersistent: false
    property string stowScreen: ""
    // 搬家模式（第三段）：栏背景空白处向屏内拉过 110px 进入；moveEdge 为
    // 指针最近边（松手即停靠该边，走同一 setBarDirection）；同边松手不换
    // 方向、只按抽屉规则（向内 >24 已在 24px 处开了持久抽屉）。单屏拖拽，
    // 故用全局状态（与拖拽幽灵 drag* 同款）；预览窗读它显示最近边。
    property bool moveActive: false
    property string moveScreen: ""
    property string moveEdge: "top"

    // 临时模式落位后自动收起：两个区的控制器在 dragEnd 正常收尾时统一调
    // scheduleStowClose()，300ms 后关闭（让落位结果先被看见）；
    // 延迟期内任一区开始新拖拽会调 cancelStowClose() 取消，避免连续整理时被关掉。
    // 注：本单例是 QtObject、无默认子属性，Timer 只能以属性对象形式持有
    property Timer stowCloseTimer: Timer {
        interval: 300
        repeat: false
        onTriggered: { root.stowOpen = false; root.stowPersistent = false; }
    }
    function scheduleStowClose() { stowCloseTimer.restart(); }
    function cancelStowClose() { stowCloseTimer.stop(); }

    // 顶栏方向：top/bottom/left/right，落盘 ~/.cache/by-mgr/qs-bar-direction。
    // 方向是全局状态（双屏同向），barWin/Bar/ToolsGroup/面板全部读它；
    // top 时一切行为与改前一致（回归守门）。FileView/Process 以属性对象
    // 形式持有（与 stowCloseTimer 同款，单例无默认子属性）。
    property string barDirection: "top"
    readonly property bool barVertical: barDirection === "left" || barDirection === "right"
    readonly property bool barBottom: barDirection === "bottom"
    // 竖贴宽度：与启动器（Fedora 徽标块）同宽。启动器宽 = 18px 徽标字形宽 + 20，
    // 实测约 35px；Bar 用 Binding 把 launcherPill.width 实时喂进来，单点来源；
    // Pill/MusicInfo 竖条 contentW 与托盘/块 holder 竖条宽都读它。默认 35 兜底。
    property real tileW: 35
    // 天气面板弹出方向：bar 在哪边、面板就往屏内哪边弹（PopupReveal 的
    // direction 参数，内容不旋转，只换弹出方向与生长原点）
    readonly property string panelDir: barDirection === "bottom" ? "up" : (barDirection === "left" ? "right" : (barDirection === "right" ? "left" : "down"))
    property FileView directionFile: FileView {
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-direction"
        onLoaded: {
            var d = text().trim();
            if (d === "top" || d === "bottom" || d === "left" || d === "right")
                root.barDirection = d;
        }
    }
    property Process directionWriter: Process {
        command: ["bash", "-c", "true"]
    }
    function setBarDirection(d: string) {
        if (d !== "top" && d !== "bottom" && d !== "left" && d !== "right")
            return;
        if (d === root.barDirection)
            return;
        root.barDirection = d;
        root.directionWriter.command = ["bash", "-c", "printf '%s' '" + d + "' > ~/.cache/by-mgr/qs-bar-direction"];
        root.directionWriter.running = true;
    }


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
        if (except !== "cc")
            root.ccOpen = false;
        if (except !== "weather")
            root.weatherOpen = false;
        if (except !== "sidebar") {
            root.sidebarOpen = false;
            root.sidebarWallpaper = false;
        }
        if (except !== "wallpicker")
            root.wallpaperPickerOpen = false;
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

    function toggleWeather(screenName: string) {
        if (root.weatherOpen && root.weatherScreen === screenName)
            root.weatherOpen = false;
        else {
            root.weatherScreen = screenName;
            root.weatherOpen = true;
            root.closeOthers("weather");
        }
    }

    function toggleCC(screenName: string) {
        if (root.ccOpen && root.ccScreen === screenName)
            root.ccOpen = false;
        else {
            root.ccScreen = screenName;
            root.ccOpen = true;
            root.closeOthers("cc");
        }
    }

    function toggleSidebar(screenName: string) {
        if (root.sidebarOpen && root.sidebarScreen === screenName) {
            root.sidebarOpen = false;
            root.sidebarWallpaper = false;
        } else {
            root.sidebarScreen = screenName;
            root.sidebarOpen = true;
            root.closeOthers("sidebar");
        }
    }

    function toggleWallpaperPicker(screenName: string) {
        if (root.wallpaperPickerOpen && root.wallpaperPickerScreen === screenName) {
            root.wallpaperPickerOpen = false;
        } else {
            root.wallpaperPickerScreen = screenName;
            root.wallpaperPickerOpen = true;
            root.closeOthers("wallpicker");
        }
    }

    // 天气面板（锚点下拉，动画在 PopupReveal，内容在 WeatherPanel）
    property bool weatherOpen: false
    property string weatherScreen: ""

    // 通知中心
    property bool notifOpen: false
    property string notifScreen: ""
    // 中心浮窗用快照锚（按屏分键）：打开瞬间定死，之后清零计数导致 pill
    // 变窄也不跟跳
    property var notifSnap: ({})
}
