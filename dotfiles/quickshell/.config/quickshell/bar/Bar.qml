import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import Quickshell.Services.SystemTray
import Quickshell.Widgets
import "../components" as Comp
import "." as BarMod

// 顶栏：完整移植 waybar 双屏配置
// 左：launcher workspaces recorder screenshot picker clipboard gammastep theme screen-power music cava mprev mplay mnext lyric
// 右：updates weather pulseaudio brightness/cpu/power-profiles/memory/network/bluetooth/battery/clock/tray/fcitx/inhibit/power
Item {
    id: root
    property var theme
    property var hostWindow: null
    property string screenName: ""
    // HDMI-A-1 用 ddcutil 外接屏亮度，eDP-1 用 waybar brightness.sh
    property bool isExternal: screenName === "HDMI-A-1"
    // 竖条方向：bar 在左右边时整栏竖排。根由 RowLayout 改为 Item +
    // hLay/vLay 双布局：布局孩子（启动器/工作区/工具组/音乐簇/间隔/
    // 胶囊区）在方向切换时整体 reparent 到激活布局；非激活胶囊区
    // （模型已切空）归回根下隐藏。横向行为与改前一致（回归守门）。
    property bool vertical: Comp.UiState.barVertical
    // 竖贴宽度喂给 UiState.tileW：启动器宽是固定值 34.8（fixedWidth，与徽标
    // 字形尺寸解耦，图标改 14px 不动宽度）；Pill/MusicInfo/托盘/块 holder
    // 的竖条宽都读它，与启动器同宽。
    Binding { target: Comp.UiState; property: "tileW"; value: launcherPill.width }
    onVerticalChanged: root.applyOrientation()
    RowLayout {
        id: hLay
        anchors.fill: parent
        spacing: 2
        visible: !root.vertical
    }
    ColumnLayout {
        id: vLay
        anchors.fill: parent
        spacing: 1
        visible: root.vertical
    }
    // 方向切换时的布局孩子搬运：激活布局接 6 件（胶囊区取激活的那个），
    // 闲置胶囊区归回根下隐藏（模型已空，不占位）；块归位一并复核
    // （抽屉 holder 里的工作区列需按竖条重新居中）
    function applyOrientation() {
        var lay = root.vertical ? vLay : hLay;
        var kids = [launcherWrap, workspacesWrap, toolsGroup, musicWrap, barSpacer, root.vertical ? pillZoneV : pillZone];
        for (var i = 0; i < kids.length; i++) {
            if (kids[i] && kids[i].parent !== lay)
                kids[i].parent = lay;
        }
        var idle = root.vertical ? pillZone : pillZoneV;
        if (idle) {
            idle.visible = false;
            if (idle.parent !== root)
                idle.parent = root;
        }
        var active = root.vertical ? pillZoneV : pillZone;
        if (active)
            active.visible = true;
        root.applyBlockPlacement();
    }

    // 整栏一次性淡入：等调色板就位后再现身，避免先以 fallback 色淡入再跳变；
    // 5 秒兜底（无调色板文件时用 fallback 色直接显示）
    property bool paletteTimeout: false
    Timer {
        interval: 5000
        running: true
        onTriggered: root.paletteTimeout = true
    }
    opacity: (Comp.UiState.animReady && (Comp.PaletteState.blob !== "" || root.paletteTimeout)) ? 1 : 0
    Behavior on opacity { NumberAnimation { duration: 350; easing.type: Easing.OutCubic } }

    // ---------- 胶囊拖拽区（右侧整排 17 个逻辑槽）----------
    // zoneLayout = 有序槽位表，槽位是 id 数组：单元素 = 单颗，多元素 = 组合胶囊。
    // "bri" 是逻辑槽（内接/外接两颗亮度装在 briBox 里领养）；"tray" 固定：
    // 不可拖、不可被合并（命中只给 insert），校验时必须独占单槽恰出现一次。
    // 启动时 FileView 读 qs-bar-layout.json 校验后采用（旧 6-id 格式自动迁移），
    // 拖拽落位即写回。幽灵不在栏内画，状态发布到 UiState 由 shell 覆盖窗渲染。
    property var pillMap: ({})
    property var defaultZoneLayout: [["updates"], ["weather"], ["audio"], ["bri"], ["cpu"], ["pp"], ["mem"], ["net"], ["bt"], ["bat"], ["clock"], ["bell"], ["tray"], ["fcitx"], ["inhibit"], ["cc"], ["power"]]
    property var zoneLayout: defaultZoneLayout
    property bool zoneReady: false

    // 拖拽命中带区（窗口坐标）：top 与 bottom 镜像——bottom 时栏带在窗下部
    // （48..94）、抽屉带在窗上部（0..42），带区各向外扩 12/6px 容差；
    // 槽位级命中用槽位实际坐标（自动跟随），这里只参数化带区常量。
    property bool barBottom: Comp.UiState.barDirection === "bottom"
    property bool barLeft: Comp.UiState.barDirection === "left"
    property bool barRight: Comp.UiState.barDirection === "right"
    property real bandBarY0: barBottom ? 36 : -12
    property real bandBarY1: barBottom ? 106 : 58
    property real bandStowY0: barBottom ? 2 : 48
    property real bandStowY1: barBottom ? 46 : 92
    property var slotItems: []
    property string dragId: ""
    property bool dragEnding: false   // pillDragEnd 重入守卫：落位 reparent 会同步触发 onCanceled 重入
    property int dragFromSlot: -1
    property string dragTargetType: "none"
    property int dragTargetIndex: -1
    property int dragHighlightIndex: -1
    property string dragHighlightMode: ""
    // 插入缝迟滞状态（按带各一份，-1 = 本次拖动尚未定缝），见 settleInsertSeam
    property int seamHystBar: -1
    property int seamHystStow: -1

    // ---------- 整组拖拽（长按抓组，与单颗 pillDrag 并行）----------
    // Pill 长按 280ms 发 pressHeld → pillPressHeld 判定源槽成员 ≥2 才抓组：
    // groupIds = 源槽全体成员，整组作为一个 slot 整体搬运。命中判定与单颗
    // 同构（另记 groupMergeBefore：合并时被拖组排在目标成员之前/之后），
    // 落位在 groupDragEnd 里按双区副本摘整槽/插整槽，保存路径与单颗共用。
    property bool groupActive: false
    property var groupIds: []
    property string groupFromZone: "bar"
    property int groupFromSlot: -1
    property string groupTargetType: "none"
    property int groupTargetIndex: -1
    property string groupTargetZone: "bar"
    property bool groupMergeBefore: false

    // ---------- 收纳抽屉（右区）----------
    // stowLayout = 已收纳槽位表（与 zoneLayout 同构），单独存 qs-bar-layout-stowed.json。
    // 校验改为联合：zoneLayout ∪ stowLayout 恰覆盖 17 id 各一次（见 maybeFinalizeLayouts），
    // 不合法回退为默认 17 单颗 + 收纳空。两份文件各自解析为候选（barFileCand/stowFileCand），
    // 都回执（或 500ms 兜底）后一次性定案，避免半套布局先渲染。
    property var stowLayout: []
    property var stowSlotItems: []
    property string dragFromZone: "bar"
    property string dragTargetZone: "bar"
    property int dragStowHighlightIndex: -1
    property string dragStowHighlightMode: ""
    property var barFileCand: null
    property var stowFileCand: null
    property bool barFileSettled: false
    property bool stowFileSettled: false
    property bool layoutsFinalized: false
    property var toolsGroupRef: toolsGroup
    property var stowDelegateRef: stowSlotDelegate
    // 本屏抽屉是否展开（UiState 按屏分键）
    property bool stowOpenHere: Comp.UiState.stowOpen && Comp.UiState.stowScreen === root.screenName

    // ---------- 整块收纳（启动器/工作区/音乐簇/托盘）----------
    // 四块不是槽位胶囊，不进 zoneLayout/stow 模型：各一个 stowed 布尔，存
    // qs-bar-blocks.json（缺文件/非法=全 false）。stowed=false 时本体在家
    // （启动器/工作区/音乐簇在常驻 wrapper 里、托盘在 tray 槽 holder 里）；
    // stowed=true 时本体被壳层抽屉条带里的 blockHolder 领养，家宽归 0 不留洞。
    // 抽屉 holder 由 blockHolderDelegate 生成并注册到 blockHolders（与 registerSlot 同构）。
    property var blockOrder: ["launcher", "workspaces", "music", "tray"]
    property var blockStowed: ({ "launcher": false, "workspaces": false, "music": false, "tray": false })
    property var blockHolders: ({})
    property var blockOverlays: ({})
    property var trayHolder: null
    property bool blocksSettled: false
    property var blockHolderDelegateRef: blockHolderDelegate

    FileView {
        id: blocksFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-blocks.json"
        onLoaded: { root.applyBlocksFile(text()); root.blocksSettled = true; root.applyBlockPlacement(); }
        onLoadFailed: { root.blocksSettled = true; root.applyBlockPlacement(); }
    }
    Timer {
        interval: 500
        running: true
        onTriggered: { root.blocksSettled = true; root.applyBlockPlacement(); }
    }
    function applyBlocksFile(txt) {
        try {
            var d = JSON.parse(txt);
            var o = { "launcher": false, "workspaces": false, "music": false, "tray": false };
            for (var k in o)
                if (d && d[k] === true)
                    o[k] = true;
            root.blockStowed = o;
            console.warn("[blocks] stowed " + JSON.stringify(o));
        } catch (e) {
            return;
        }
    }
    function writeBlocksFile() {
        console.warn("[blocks] stowed " + JSON.stringify(root.blockStowed));
        Comp.Exec.sh("printf '%s' '" + JSON.stringify(root.blockStowed) + "' > ~/.cache/by-mgr/qs-bar-blocks.json");
    }
    function setBlockStowed(key, v) {
        if (root.blockStowed[key] === v)
            return;
        var o = Object.assign({}, root.blockStowed);
        o[key] = v;
        root.blockStowed = o;
        root.applyBlockPlacement();
        root.writeBlocksFile();
    }
    function blockBody(key) {
        if (key === "launcher") return launcherPill;
        if (key === "workspaces") return workspacesBody;
        if (key === "music") return musicCluster;
        if (key === "tray") return trayBox;
        return null;
    }
    function blockBodyWidth(key) {
        var b = root.blockBody(key);
        if (!b)
            return 0;
        if (key === "tray")
            return b.visible ? b.width : 0;
        return b.width;
    }
    // 竖条抽屉 holder 高：启动器取方块贴高、工作区/音乐簇取隐含高、
    // 托盘取竖排高（本体在抽屉里时才量，横向不走这里）
    function blockBodyHeight(key) {
        var b = root.blockBody(key);
        if (!b)
            return 0;
        if (key === "launcher") return b.height;
        if (key === "workspaces") return b.implicitHeight;
        if (key === "music") return b.implicitHeight;
        if (key === "tray") return b.visible ? b.height : 0;
        return 0;
    }
    function registerBlockHolder(key, item) {
        var m = Object.assign({}, root.blockHolders);
        m[key] = item;
        root.blockHolders = m;
        root.applyBlockPlacement();
    }
    function unregisterBlockHolder(key, item) {
        if (root.blockHolders[key] === item) {
            var m = Object.assign({}, root.blockHolders);
            delete m[key];
            root.blockHolders = m;
        }
    }
    // 本体归位：stowed → 抽屉 holder；否则 → 家。holder 未注册时跳过（注册时会再补位）。
    // 工作区的 y 由它自己的 verticalCenter 锚管理（栏内本体 24 高、居中于 32），不手动设。
    function applyBlockPlacement() {
        root.placeBlockBody("launcher", launcherPill, launcherWrap);
        root.placeBlockBody("workspaces", workspacesBody, workspacesWrap);
        root.placeBlockBody("music", musicCluster, musicWrap);
        root.placeBlockBody("tray", trayBox, root.trayHolder);
        root.placeBlockOverlay("workspaces", workspacesWrap);
        root.placeBlockOverlay("music", musicWrap);
        Qt.callLater(root.checkBlocks);
    }
    function placeBlockBody(key, body, home) {
        if (!body)
            return;
        if (root.blockStowed[key]) {
            var h = root.blockHolders[key];
            if (h) {
                if (body.parent !== h)
                    body.parent = h;
                // 竖条抽屉 holder 宽与启动器同宽、工作区列宽 24，居中放；其余本体
                // 宽即 holder 宽、x=0 即居中，横向一律 x=0 不变。
                // x/y 每次都重算（不只换亲时）：方向翻转后已在 holder 里
                // 的本体也要按新方向重新居中。
                body.x = (root.vertical && key === "workspaces") ? (h.width - body.implicitWidth) / 2 : 0;
                if (key !== "workspaces")
                    body.y = 0;
            }
        } else if (home && body.parent !== home) {
            body.parent = home;
            body.x = 0;
            if (key !== "workspaces")
                body.y = 0;
        }
    }
    function placeBlockOverlay(key, home) {
        var overlay = root.blockOverlays[key];
        if (!overlay)
            return;
        if (root.blockStowed[key]) {
            var h = root.blockHolders[key];
            if (h && overlay.parent !== h)
                overlay.parent = h;
        } else if (home && overlay.parent !== home) {
            overlay.parent = home;
        }
    }
    // 块自检（与 pill orphan 同构）：本体必须恰在预期的家或抽屉 holder 里，否则打 warn 留证
    function checkBlocks() {
        root.checkOneBlock("launcher", launcherPill, launcherWrap);
        root.checkOneBlock("workspaces", workspacesBody, workspacesWrap);
        root.checkOneBlock("music", musicCluster, musicWrap);
        root.checkOneBlock("tray", trayBox, root.trayHolder);
    }
    function checkOneBlock(key, body, home) {
        if (!body)
            return;
        var expect = root.blockStowed[key] ? root.blockHolders[key] : home;
        if (expect && body.parent !== expect)
            console.warn("[blocks] misplaced " + key + " stowed=" + root.blockStowed[key]);
    }

    FileView {
        id: layoutFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-layout.json"
        // 定案后本实例的实时模型即归属真源：watcher 回读（含本实例自己写盘
        // 的回声、另一屏实例的写盘）一律忽略，文件只在启动定案前读——
        // 否则回读候选 churn 会让重启采用不稳定（2026-10-22 竞态收尾）
        onLoaded: { if (root.layoutsFinalized) return; root.applyLayoutFile(text()); root.barFileSettled = true; root.maybeFinalizeLayouts(false); }
        onLoadFailed: { if (root.layoutsFinalized) return; root.barFileSettled = true; root.maybeFinalizeLayouts(false); }
    }
    FileView {
        id: stowFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-layout-stowed.json"
        onLoaded: { if (root.layoutsFinalized) return; root.applyStowFile(text()); root.stowFileSettled = true; root.maybeFinalizeLayouts(false); }
        onLoadFailed: { if (root.layoutsFinalized) return; root.stowFileCand = []; root.stowFileSettled = true; root.maybeFinalizeLayouts(false); }
    }
    // 兜底定案：两份文件都回执后由 onLoaded 路定案；只有某份迟迟不回执
    // （>3s）才强制用现有候选定案，不让整区空白——旧实现 500ms 一到就
    // 强制定案，一份文件慢半拍便整会话回退默认布局（重启采用不稳定）
    property int finalizeTicks: 0
    Timer {
        interval: 500
        running: true
        repeat: true
        onTriggered: {
            root.finalizeTicks++;
            if (root.layoutsFinalized) { stop(); return; }
            if (root.barFileSettled && root.stowFileSettled) { root.maybeFinalizeLayouts(false); stop(); return; }
            if (root.finalizeTicks >= 6) { root.maybeFinalizeLayouts(true); stop(); }
        }
    }
    Component.onCompleted: {
        root.pillMap = { "updates": updatesPill, "weather": weatherPill, "audio": audioPill, "bri": briBox, "cpu": cpuPill, "pp": ppPill, "mem": memPill, "net": netPill, "bt": btPill, "bat": batPill, "clock": clockPill, "bell": bellPill, "tray": trayBox, "fcitx": fcitxPill, "inhibit": inhibitPill, "cc": ccPill, "power": powerPill };
        console.warn("[pillzone] layout " + JSON.stringify(root.zoneLayout));
        // 整块拖拽层：启动器/托盘挂本体（Rectangle，可带子项）；工作区/音乐簇的
        // 本体是 Row/RowLayout（子 MouseArea 会被当排布项），挂在与本体同进同出的
        // wrapper 上，归位时由 placeBlockOverlay 跟本体一同搬
        root.attachBlockLayer("launcher", launcherPill, launcherPill);
        root.attachBlockLayer("workspaces", workspacesBody, workspacesWrap);
        root.attachBlockLayer("music", musicCluster, musicWrap);
        root.attachBlockLayer("tray", trayBox, trayBox);
        // 整组拖拽信号一次接线：pill 是长命对象，接一次即可（delegate 重建
        // 不重复接）。pillMap 里的 briBox/trayBox 不是 Pill（无这组信号）跳过；
        // "bri" 的按下实体是 briBox 内的两颗，单独接。
        for (var gpid in root.pillMap)
            root.connectGroupSignals(root.pillMap[gpid]);
        root.connectGroupSignals(briIntPill);
        root.connectGroupSignals(briExtPill);
        // 首帧即按当前方向把布局孩子放进激活布局（否则全挤在根原点）
        root.applyOrientation();
    }
    function connectGroupSignals(p) {
        if (!p || !p.pressHeld)
            return;
        p.pressHeld.connect(function(pill) { root.pillPressHeld(pill); });
        p.groupDragMoved.connect(function(wx, wy) { root.groupDragMoved(wx, wy); });
        p.groupDragEnded.connect(function() { root.groupDragEnd(); });
    }

    // 窗口坐标：逐级累加祖先 x/y（本 Qt 版本 mapToItem(null) 不可靠，见 Pill.updateAnchor）
    function absPosOf(it) {
        var x = 0, y = 0, n = it;
        var guard = 0;
        while (n && guard++ < 100) {
            x += n.x;
            y += n.y;
            n = n.parent;
        }
        return Qt.point(x, y);
    }
    function registerSlot(idx, item) {
        var a = root.slotItems;
        a[idx] = item;
        root.slotItems = a;
    }
    function unregisterSlot(idx, item) {
        // 按下标置空，禁止 splice：registerSlot 按下标写入，删除若移位会让
        // slotItems 与 zoneLayout 下标错位（命中判定/落位全错，两端最明显）
        var a = root.slotItems;
        if (idx >= 0 && idx < a.length && a[idx] === item)
            a[idx] = null;
        root.slotItems = a;
    }
    function applyLayoutFile(txt) {
        var known17 = ["updates", "weather", "audio", "bri", "cpu", "pp", "mem", "net", "bt", "bat", "clock", "bell", "tray", "fcitx", "inhibit", "cc", "power"];
        var known6 = ["cpu", "pp", "mem", "net", "bt", "bat"];
        // 槽位表合法性：数组的数组、槽非空、id 恰好把 known 各覆盖一次
        function validLayout(data, known) {
            if (!Array.isArray(data))
                return false;
            var seen = {};
            for (var i = 0; i < data.length; i++) {
                if (!Array.isArray(data[i]) || data[i].length === 0)
                    return false;
                for (var j = 0; j < data[i].length; j++) {
                    if (typeof data[i][j] !== "string" || known.indexOf(data[i][j]) < 0 || seen[data[i][j]])
                        return false;
                    seen[data[i][j]] = true;
                }
            }
            return Object.keys(seen).length === known.length;
        }
        try {
            var data = JSON.parse(txt);
            if (validLayout(data, known17)) {
                // tray 固定：必须独占单槽
                var trayOk = false;
                for (var i = 0; i < data.length; i++)
                    if (data[i].length === 1 && data[i][0] === "tray")
                        trayOk = true;
                if (!trayOk)
                    return;
                root.barFileCand = data;
                return;
            }
            if (validLayout(data, known6)) {
                // 旧 6-id 格式迁移：旧槽位原样替换默认布局中 cpu..bat 的 6 个单颗，
                // 其余槽位用默认单颗补齐，迁移结果回写为新格式。
                var out = [];
                for (var k = 0; k < root.defaultZoneLayout.length; k++) {
                    var s0 = root.defaultZoneLayout[k][0];
                    if (s0 === "cpu") {
                        for (var m = 0; m < data.length; m++)
                            out.push(data[m]);
                    } else if (known6.indexOf(s0) < 0) {
                        out.push(root.defaultZoneLayout[k]);
                    }
                }
                root.barFileCand = out;
                console.warn("[pillzone] layout " + JSON.stringify(out));
                Comp.Exec.sh("printf '%s' '" + JSON.stringify(out).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout.json");
                return;
            }
            if (validSlots(data, known17)) {
                // 拆分持久化（bar/stow 两文件分存）时 bar 文件只覆盖一部分 id：
                // 形状合法（槽非空、id 已知、表内不重复）即收为候选，覆盖
                // 完整性与 tray 独占由 maybeFinalizeLayouts 联合校验把关——
                // 与左区 ToolsGroup.applyLayoutFile 的收候选口径一致。此前这里
                // 只有「单独覆盖 17」与「旧 6 迁移」两条路，抽屉非空时重启
                // 必然回退默认布局（2026-10-22 实测：bar 5 + stow 12 被拒收）。
                root.barFileCand = data;
                return;
            }
        } catch (e) {
            return;
        }
    }
    // 槽位表形状校验（不查覆盖）：数组的数组、槽非空、id 属于 known、表内不重复
    function validSlots(data, known) {
        if (!Array.isArray(data))
            return false;
        var seen = {};
        for (var i = 0; i < data.length; i++) {
            if (!Array.isArray(data[i]) || data[i].length === 0)
                return false;
            for (var j = 0; j < data[i].length; j++) {
                if (typeof data[i][j] !== "string" || known.indexOf(data[i][j]) < 0 || seen[data[i][j]])
                    return false;
                seen[data[i][j]] = true;
            }
        }
        return true;
    }
    function applyStowFile(txt) {
        try {
            var data = JSON.parse(txt);
            if (Array.isArray(data))
                root.stowFileCand = data;
        } catch (e) {
            return;
        }
    }
    // 联合定案：bar 候选 ∪ stow 候选恰覆盖 17 id 且 tray 独占单槽在 bar 段才采用，
    // 否则回退默认 17 单颗 + 收纳空（两文件任一损坏都不至于整区消失）
    function maybeFinalizeLayouts(force) {
        if (root.layoutsFinalized)
            return;
        if (!force && !(root.barFileSettled && root.stowFileSettled))
            return;
        root.layoutsFinalized = true;
        var known = ["updates", "weather", "audio", "bri", "cpu", "pp", "mem", "net", "bt", "bat", "clock", "bell", "tray", "fcitx", "inhibit", "cc", "power"];
        var bar = root.barFileCand;
        var stow = root.stowFileCand;
        var ok = false;
        if (validSlots(bar, known) && validSlots(stow, known)) {
            var seen = {};
            var cnt = 0;
            var trayOk = false;
            for (var i = 0; i < bar.length; i++) {
                if (bar[i].length === 1 && bar[i][0] === "tray")
                    trayOk = true;
                for (var j = 0; j < bar[i].length; j++) { seen[bar[i][j]] = true; cnt++; }
            }
            for (var k = 0; k < stow.length; k++)
                for (var m = 0; m < stow[k].length; m++) { seen[stow[k][m]] = true; cnt++; }
            ok = trayOk && cnt === known.length && Object.keys(seen).length === known.length;
        }
        if (ok) {
            root.zoneLayout = bar;
            root.stowLayout = stow;
        } else {
            root.zoneLayout = root.defaultZoneLayout;
            root.stowLayout = [];
        }
        console.warn("[pillzone] layout " + JSON.stringify(root.zoneLayout));
        console.warn("[pillzone] stow " + JSON.stringify(root.stowLayout));
        root.zoneReady = true;
        root.applyFrozen();
    }
    function registerStowSlot(idx, item) {
        var a = root.stowSlotItems;
        a[idx] = item;
        root.stowSlotItems = a;
    }
    function unregisterStowSlot(idx, item) {
        // 同 unregisterSlot：按下标置空，禁止 splice
        var a = root.stowSlotItems;
        if (idx >= 0 && idx < a.length && a[idx] === item)
            a[idx] = null;
        root.stowSlotItems = a;
    }
    function stowHas(pid) {
        for (var i = 0; i < root.stowLayout.length; i++)
            if (root.stowLayout[i].indexOf(pid) >= 0)
                return true;
        return false;
    }
    // 冻结（已收纳 && 本屏抽屉关闭）：可真停的只有带 per-pill exec 的 ScriptPill
    // （updates/weather/audio/briExt/fcitx）与时钟秒表；其余 pill 的文案来自
    // BarState 共享轮询（单进程喂全栏 + 双屏共用），无法按 pill 拆，保持运行。
    function applyFrozen() {
        var f = !root.stowOpenHere;
        updatesPill.frozen = f && root.stowHas("updates");
        weatherPill.frozen = f && root.stowHas("weather");
        audioPill.frozen = f && root.stowHas("audio");
        briExtPill.frozen = f && root.stowHas("bri");
        fcitxPill.frozen = f && root.stowHas("fcitx");
        clockPill.frozen = f && root.stowHas("clock");
    }
    // 抽屉打开：收纳中的 ScriptPill 各补刷一次，时钟立即对时
    function refreshStowed() {
        if (root.stowHas("updates")) updatesPill.refresh();
        if (root.stowHas("weather")) weatherPill.refresh();
        if (root.stowHas("audio")) audioPill.refresh();
        if (root.stowHas("bri")) briExtPill.refresh();
        if (root.stowHas("fcitx")) fcitxPill.refresh();
        if (root.stowHas("clock")) clockPill.clockDate = new Date();
    }
    Connections {
        target: Comp.UiState
        function onStowOpenChanged() {
            root.applyFrozen();
            if (Comp.UiState.stowOpen && root.stowOpenHere)
                root.refreshStowed();
        }
        function onStowScreenChanged() { root.applyFrozen(); }
    }
    onStowLayoutChanged: root.applyFrozen()
    // 布局变更前把 pill 送回仓库，避免 Repeater 重建 delegate 时连带销毁。
    // 只营救「本次真的变了」的区：未变的那份布局赋的是深相等数组，QML 不
    // 发变更通知、Repeater 不重建——若把未变区的 pill 也一并营救，它们
    // 永远没人领养、整区滞留仓库变空白（2026-10-22 实测：bar 内换位 →
    // 抽屉 10 颗 orphan；抽屉内换位 → bar 12 颗 orphan，方向对称）
    function rescueAllPills(rescueBar, rescueStow) {
        if (rescueBar) {
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s)
                    continue;
                for (var j = 0; j < s.members.length; j++) {
                    // 托盘整块收纳中：本体在抽屉里，不参与胶囊营救（随后 applyBlockPlacement 复核）
                    if (s.members[j] === trayBox && root.blockStowed.tray)
                        continue;
                    s.members[j].bare = false;
                    s.members[j].drawerMode = false;
                    s.members[j].vertical = false;
                    s.members[j].parent = pillWarehouse;
                }
            }
        }
        if (rescueStow) {
            // 收纳槽：跨区落位（bar↔抽屉）时成员可能在抽屉 holder 里
            for (var i2 = 0; i2 < root.stowSlotItems.length; i2++) {
                var s2 = root.stowSlotItems[i2];
                if (!s2)
                    continue;
                for (var j2 = 0; j2 < s2.members.length; j2++) {
                    if (s2.members[j2] === trayBox && root.blockStowed.tray)
                        continue;
                    s2.members[j2].bare = false;
                    s2.members[j2].drawerMode = false;
                    s2.members[j2].vertical = false;
                    s2.members[j2].parent = pillWarehouse;
                }
            }
        }
    }
    // 在槽 delegate 子树里按 pillId+pillRef 找成员的占位 holder（领养凭证）
    function findSlotHolder(slotItem, pid, pillObj) {
        if (!slotItem)
            return null;
        var stack = [slotItem];
        var guard = 0;
        while (stack.length > 0 && guard++ < 200) {
            var n = stack.pop();
            if (!n)
                continue;
            if (n.pillId === pid && n.pillRef === pillObj)
                return n;
            var ch = n.children;
            if (ch)
                for (var ci = 0; ci < ch.length; ci++)
                    stack.push(ch[ci]);
        }
        return null;
    }
    // 落位自愈（兜底）：仍滞留仓库的 pill 按当前模型确定性地送回其槽的
    // holder，不靠 Repeater 重建时序；送不回去的留给调用方打 orphan 留证
    function healOrphans() {
        var healed = [];
        for (var oid in root.pillMap) {
            var p = root.pillMap[oid];
            if (!p || p.parent !== pillWarehouse)
                continue;
            // 托盘整块收纳中本体归抽屉块 holder 管（applyBlockPlacement），不走槽领养
            if (oid === "tray" && root.blockStowed.tray)
                continue;
            var zone = "", sidx = -1;
            for (var i = 0; i < root.zoneLayout.length; i++)
                if (root.zoneLayout[i].indexOf(oid) >= 0) { zone = "bar"; sidx = i; break; }
            if (sidx < 0)
                for (var j = 0; j < root.stowLayout.length; j++)
                    if (root.stowLayout[j].indexOf(oid) >= 0) { zone = "stow"; sidx = j; break; }
            if (sidx < 0)
                continue;
            var slotItem = zone === "bar" ? root.slotItems[sidx] : root.stowSlotItems[sidx];
            var holder = root.findSlotHolder(slotItem, oid, p);
            if (!holder)
                continue;
            p.parent = holder;
            p.x = 0;
            p.y = 0;
            p.bare = (zone === "bar" ? root.zoneLayout[sidx] : root.stowLayout[sidx]).length >= 2;
            p.drawerMode = (zone === "stow");
            p.vertical = root.vertical;
            healed.push(oid);
        }
        if (healed.length > 0)
            console.warn("[pillzone] healed " + healed.join(","));
    }
    function pillDragStart(pid) {
        root.dragId = pid;
        root.dragFromZone = "bar";
        root.dragFromSlot = -1;
        for (var i = 0; i < root.zoneLayout.length; i++) {
            if (root.zoneLayout[i].indexOf(pid) >= 0) {
                root.dragFromSlot = i;
                break;
            }
        }
        if (root.dragFromSlot < 0) {
            for (var j = 0; j < root.stowLayout.length; j++) {
                if (root.stowLayout[j].indexOf(pid) >= 0) {
                    root.dragFromZone = "stow";
                    root.dragFromSlot = j;
                    break;
                }
            }
        }
        var pill = root.pillMap[pid];
        if (pill) {
            var ap = root.absPosOf(pill);
            // 幽灵发布给 shell 覆盖窗（先填内容再置 active，避免首帧旧值）
            Comp.UiState.dragText = pill.pillText;
            Comp.UiState.dragBg = pill.normalBg;
            Comp.UiState.dragFg = pill.normalFg;
            Comp.UiState.dragW = Math.max(pill.width, 40);
            Comp.UiState.dragH = pill.height;
            Comp.UiState.dragX = ap.x + pill.width / 2;
            Comp.UiState.dragY = ap.y + 16;
        }
        Comp.UiState.dragScreen = root.screenName;
        Comp.UiState.dragActive = true;
        // 起拖即展开收纳层（临时模式），并取消上次落位预约的自动收起；
        // 若本屏已是背景手势的持久打开，模式保持不变、拖拽不降级它
        if (!(Comp.UiState.stowOpen && Comp.UiState.stowPersistent && Comp.UiState.stowScreen === root.screenName))
            Comp.UiState.stowPersistent = false;
        Comp.UiState.stowScreen = root.screenName;
        Comp.UiState.stowOpen = true;
        Comp.UiState.cancelStowClose();
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
        root.dragTargetZone = "bar";
        root.dragStowHighlightIndex = -1;
        root.dragStowHighlightMode = "";
        root.seamHystBar = -1;
        root.seamHystStow = -1;
    }
    // 插入缝唯一化 + 迟滞（2026-10-22 修插入线在缝两侧跳变）：
    // 同一条缝原先有两个表示——左槽的 insertR 与右槽的 insertL，delegate
    // 画线 x 相差 6px（左槽右缘 +3 / 右槽左缘 -5），指针在缝附近微动、
    // 悬停槽一翻面，线就在两个位置间跳。现统一：缝只以下标 s 表示
    // （fx 边缘区与中点规则等价：fx<0.22 必在槽中点左侧 → 缝 = 槽下标，
    // fx>0.78 必在中点右侧 → 缝 = 槽下标 + 1；间隙兜底本就按中点取缝），
    // 高亮一律规范为「缝后槽的 insertL」（末缝用末槽的 insertR），delegate
    // 画线也已对齐到缝的几何间隙本身（insertL x=-2 / insertR x=width，
    // 正好盖住 spacing 2 的缝），两个来源画出的是同一条线。
    // 迟滞：本带上次定下的缝 prev 未变时，换缝须指针越过 prev 相邻槽的
    // 中点再 ±4px 才放行，临界处不抖；落位用的 tIndex 经此定案，所见即所落。
    function settleInsertSeam(band, rawSeam, wx) {
        var items = band === "stow" ? root.stowSlotItems : root.slotItems;
        var prev = band === "stow" ? root.seamHystStow : root.seamHystBar;
        var seam = rawSeam;
        if (prev >= 0 && rawSeam !== prev && items.length > 0) {
            if (rawSeam > prev) {
                // 向右换缝：分界 = prev 缝右侧槽（下标 prev）的中点
                var rit = items[Math.min(prev, items.length - 1)];
                if (rit) {
                    var rm = root.absPosOf(rit).x + rit.width / 2;
                    if (wx <= rm + 4)
                        seam = prev;
                }
            } else if (prev >= 1) {
                // 向左换缝：分界 = prev 缝左侧槽（下标 prev-1）的中点
                var lit = items[prev - 1];
                if (lit) {
                    var lm = root.absPosOf(lit).x + lit.width / 2;
                    if (wx >= lm - 4)
                        seam = prev;
                }
            }
        }
        if (band === "stow")
            root.seamHystStow = seam;
        else
            root.seamHystBar = seam;
        return seam;
    }
    // 缝下标 → 规范高亮（缝后槽 insertL；末缝用末槽 insertR；无槽不高亮）
    function seamHighlight(band, seam) {
        var n = (band === "stow" ? root.stowSlotItems : root.slotItems).length;
        if (n <= 0)
            return [-1, ""];
        if (seam < n)
            return [seam, "insertL"];
        return [n - 1, "insertR"];
    }

    // ---------- 竖条拖拽命中（与横向同构，轴互换）----------
    // 栏带与抽屉带沿 x 分（左栏：栏 -12..68、抽屉 56..124；右栏以 winW
    // 镜像），长轴沿 y：槽内 fy 0.22/0.78 边缘、中心 merge、tray 只给
    // insert，间隙兜底按槽中心定插入点；缝迟滞用 V 版（y 中点 ±4px），
    // 高亮规范化复用 seamHighlight（与轴无关）。空白落位：抽屉带全高
    // 适用；栏带限胶囊列纵向范围 ±24（组拖）/ ±10（单颗间隙兜底）。
    function settleInsertSeamV(band, rawSeam, wy) {
        var items = band === "stow" ? root.stowSlotItems : root.slotItems;
        var prev = band === "stow" ? root.seamHystStow : root.seamHystBar;
        var seam = rawSeam;
        if (prev >= 0 && rawSeam !== prev && items.length > 0) {
            if (rawSeam > prev) {
                var rit = items[Math.min(prev, items.length - 1)];
                if (rit) {
                    var rm = root.absPosOf(rit).y + rit.height / 2;
                    if (wy <= rm + 4)
                        seam = prev;
                }
            } else if (prev >= 1) {
                var lit = items[prev - 1];
                if (lit) {
                    var lm = root.absPosOf(lit).y + lit.height / 2;
                    if (wy >= lm - 4)
                        seam = prev;
                }
            }
        }
        if (band === "stow")
            root.seamHystStow = seam;
        else
            root.seamHystBar = seam;
        return seam;
    }
    function vBands() {
        var winW = root.hostWindow ? root.hostWindow.width : 100000;
        var winH = root.hostWindow ? root.hostWindow.height : 100000;
        if (root.barLeft)
            return { winW: winW, winH: winH, barX0: -12, barX1: 68, stowX0: 56, stowX1: 124 };
        return { winW: winW, winH: winH, barX0: winW - 68, barX1: winW + 12, stowX0: winW - 124, stowX1: winW - 56 };
    }
    function pillDragMovedV(wx, wy) {
        if (root.dragId === "")
            return;
        Comp.UiState.dragX = wx;
        Comp.UiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var zone = "bar", sHlIndex = -1, sHlMode = "";
        var b = root.vBands();
        var inBar = wx >= b.barX0 && wx <= b.barX1 && wy >= 0 && wy <= b.winH;
        var stowDone = false;
        if (root.stowOpenHere && wx >= b.stowX0 && wx <= b.stowX1 && wy >= 0 && wy <= b.winH) {
            var sHit = -1;
            for (var si = 0; si < root.stowSlotItems.length; si++) {
                var ss = root.stowSlotItems[si];
                if (!ss || ss.height <= 0)
                    continue;
                var ssp = root.absPosOf(ss);
                if (wy >= ssp.y && wy <= ssp.y + ss.height && wx >= ssp.x - 8 && wx <= ssp.x + ss.width + 8) {
                    sHit = si;
                    var sfy = (wy - ssp.y) / ss.height;
                    if (sfy < 0.22) { type = "insert"; tIndex = si; sHlIndex = si; sHlMode = "insertL"; }
                    else if (sfy > 0.78) { type = "insert"; tIndex = si + 1; sHlIndex = si; sHlMode = "insertR"; }
                    else { type = "merge"; tIndex = si; sHlIndex = si; sHlMode = "merge"; }
                    break;
                }
            }
            if (sHit >= 0) {
                zone = "stow";
                stowDone = true;
            } else if (root.stowLayout.length === 0) {
                type = "insert"; tIndex = 0; zone = "stow"; stowDone = true;
            } else if (root.stowSlotItems.length > 0) {
                var sp2 = root.stowSlotItems.length;
                for (var sk2 = 0; sk2 < root.stowSlotItems.length; sk2++) {
                    var skk = root.stowSlotItems[sk2];
                    if (!skk)
                        continue;
                    var skp2 = root.absPosOf(skk);
                    if (wy < skp2.y + skk.height / 2) { sp2 = sk2; break; }
                }
                type = "insert"; tIndex = sp2; zone = "stow"; stowDone = true;
                if (sp2 < root.stowSlotItems.length) { sHlIndex = sp2; sHlMode = "insertL"; }
                else { sHlIndex = root.stowSlotItems.length - 1; sHlMode = "insertR"; }
            }
        }
        if (!stowDone && inBar) {
            var hit = -1;
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s || s.height <= 0)
                    continue;
                var sp = root.absPosOf(s);
                if (wy >= sp.y && wy <= sp.y + s.height && wx >= sp.x - 8 && wx <= sp.x + s.width + 8) {
                    hit = i;
                    var fy = (wy - sp.y) / s.height;
                    var slotIdsI = root.zoneLayout[i];
                    var isTraySlot = slotIdsI && slotIdsI.length === 1 && slotIdsI[0] === "tray";
                    if (isTraySlot) {
                        if (fy < 0.5) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                        else { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    }
                    else if (fy < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fy > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(pillZoneV);
                if (wy >= zp.y - 10 && wy <= zp.y + pillZoneV.height + 10 && wx >= zp.x - 8 && wx <= zp.x + pillZoneV.width + 8) {
                    var p = root.slotItems.length;
                    for (var k = 0; k < root.slotItems.length; k++) {
                        var sk = root.slotItems[k];
                        if (!sk)
                            continue;
                        var skp = root.absPosOf(sk);
                        if (wy < skp.y + sk.height / 2) { p = k; break; }
                    }
                    type = "insert"; tIndex = p;
                    if (p < root.slotItems.length) { hlIndex = p; hlMode = "insertL"; }
                    else { hlIndex = root.slotItems.length - 1; hlMode = "insertR"; }
                }
            }
        }
        if (type === "insert") {
            tIndex = root.settleInsertSeamV(zone, tIndex, wy);
            var shl = root.seamHighlight(zone, tIndex);
            if (zone === "stow") { sHlIndex = shl[0]; sHlMode = shl[1]; }
            else { hlIndex = shl[0]; hlMode = shl[1]; }
        }
        root.dragTargetType = type;
        root.dragTargetIndex = tIndex;
        root.dragHighlightIndex = hlIndex;
        root.dragHighlightMode = hlMode;
        root.dragTargetZone = zone;
        root.dragStowHighlightIndex = sHlIndex;
        root.dragStowHighlightMode = sHlMode;
    }
    function groupDragMovedV(wx, wy) {
        if (!root.groupActive)
            return;
        Comp.UiState.dragX = wx;
        Comp.UiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var zone = "bar", sHlIndex = -1, sHlMode = "";
        var gBefore = false;
        var b = root.vBands();
        var inBar = wx >= b.barX0 && wx <= b.barX1 && wy >= 0 && wy <= b.winH;
        var stowDone = false;
        if (root.stowOpenHere && wx >= b.stowX0 && wx <= b.stowX1 && wy >= 0 && wy <= b.winH) {
            var sHit = -1;
            for (var si = 0; si < root.stowSlotItems.length; si++) {
                var ss = root.stowSlotItems[si];
                if (!ss || ss.height <= 0)
                    continue;
                var ssp = root.absPosOf(ss);
                if (wy >= ssp.y && wy <= ssp.y + ss.height && wx >= ssp.x - 8 && wx <= ssp.x + ss.width + 8) {
                    sHit = si;
                    var sfy = (wy - ssp.y) / ss.height;
                    if (sfy < 0.22) { type = "insert"; tIndex = si; sHlIndex = si; sHlMode = "insertL"; }
                    else if (sfy > 0.78) { type = "insert"; tIndex = si + 1; sHlIndex = si; sHlMode = "insertR"; }
                    else { type = "merge"; tIndex = si; sHlIndex = si; sHlMode = "merge"; gBefore = sfy < 0.5; }
                    break;
                }
            }
            if (sHit >= 0) {
                zone = "stow";
                stowDone = true;
            } else if (root.stowLayout.length === 0) {
                type = "insert"; tIndex = 0; zone = "stow"; stowDone = true;
            } else if (root.stowSlotItems.length > 0) {
                var sp2 = root.stowSlotItems.length;
                for (var sk2 = 0; sk2 < root.stowSlotItems.length; sk2++) {
                    var skk = root.stowSlotItems[sk2];
                    if (!skk)
                        continue;
                    var skp2 = root.absPosOf(skk);
                    if (wy < skp2.y + skk.height / 2) { sp2 = sk2; break; }
                }
                type = "insert"; tIndex = sp2; zone = "stow"; stowDone = true;
                if (sp2 < root.stowSlotItems.length) { sHlIndex = sp2; sHlMode = "insertL"; }
                else { sHlIndex = root.stowSlotItems.length - 1; sHlMode = "insertR"; }
            }
        }
        if (!stowDone && inBar) {
            var hit = -1;
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s || s.height <= 0)
                    continue;
                var sp = root.absPosOf(s);
                if (wy >= sp.y && wy <= sp.y + s.height && wx >= sp.x - 8 && wx <= sp.x + s.width + 8) {
                    hit = i;
                    var fy = (wy - sp.y) / s.height;
                    var slotIdsI = root.zoneLayout[i];
                    var isTraySlot = slotIdsI && slotIdsI.length === 1 && slotIdsI[0] === "tray";
                    if (isTraySlot) {
                        if (fy < 0.5) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                        else { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    }
                    else if (fy < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fy > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; gBefore = fy < 0.5; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(pillZoneV);
                if (wy >= zp.y - 10 && wy <= zp.y + pillZoneV.height + 10 && wx >= zp.x - 8 && wx <= zp.x + pillZoneV.width + 8) {
                    var p = root.slotItems.length;
                    for (var k = 0; k < root.slotItems.length; k++) {
                        var sk = root.slotItems[k];
                        if (!sk)
                            continue;
                        var skp = root.absPosOf(sk);
                        if (wy < skp.y + sk.height / 2) { p = k; break; }
                    }
                    type = "insert"; tIndex = p;
                    if (p < root.slotItems.length) { hlIndex = p; hlMode = "insertL"; }
                    else { hlIndex = root.slotItems.length - 1; hlMode = "insertR"; }
                }
            }
        }
        // 空白落位：两带内仍未命中 → 整组作为独立槽追加到该区末尾
        if (type === "none") {
            if (root.stowOpenHere && wx >= b.stowX0 && wx <= b.stowX1 && wy >= 0 && wy <= b.winH) {
                type = "insert"; tIndex = root.stowLayout.length; zone = "stow";
            } else if (wx >= b.barX0 && wx <= b.barX1 && wy >= 0 && wy <= b.winH) {
                var bzp = root.absPosOf(pillZoneV);
                if (wy >= bzp.y - 24 && wy <= bzp.y + pillZoneV.height + 24) {
                    type = "insert"; tIndex = root.zoneLayout.length; zone = "bar";
                }
            }
        }
        if (type === "insert") {
            tIndex = root.settleInsertSeamV(zone, tIndex, wy);
            var shl = root.seamHighlight(zone, tIndex);
            if (zone === "stow") { sHlIndex = shl[0]; sHlMode = shl[1]; }
            else { hlIndex = shl[0]; hlMode = shl[1]; }
        }
        root.groupTargetType = type;
        root.groupTargetIndex = tIndex;
        root.groupTargetZone = zone;
        root.groupMergeBefore = gBefore;
        root.dragTargetType = type;
        root.dragTargetIndex = tIndex;
        root.dragTargetZone = zone;
        root.dragHighlightIndex = hlIndex;
        root.dragHighlightMode = hlMode;
        root.dragStowHighlightIndex = sHlIndex;
        root.dragStowHighlightMode = sHlMode;
    }
    function blockDragEndV(ma, wx, wy) {
        Comp.UiState.dragActive = false;
        musicCluster.opacity = 1;
        workspacesBody.opacity = 1;
        var key = ma.blockKey;
        var stowed = root.blockStowed[key];
        var b = root.vBands();
        var inY = wy >= 0 && wy <= b.winH;
        // 竖条落位（窗口坐标）：在栏上拖进抽屉带（沿 x）→ 收纳；
        // 在抽屉里拖回栏带 → 取出；其余原样不动
        if (!stowed && inY && wx >= b.stowX0 && wx <= b.stowX1)
            root.setBlockStowed(key, true);
        else if (stowed && inY && wx >= b.barX0 && wx <= b.barX1)
            root.setBlockStowed(key, false);
        if (Comp.UiState.stowPersistent)
            Comp.UiState.cancelStowClose();
        else
            Comp.UiState.scheduleStowClose();
    }
    function pillDragMoved(wx, wy) {
        if (root.vertical) { root.pillDragMovedV(wx, wy); return; }
        if (root.dragId === "")
            return;
        Comp.UiState.dragX = wx;
        Comp.UiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var zone = "bar", sHlIndex = -1, sHlMode = "";
        var winW = root.hostWindow ? root.hostWindow.width : 100000;
        var inBar = wx >= 0 && wx <= winW && wy >= root.bandBarY0 && wy <= root.bandBarY1;
        // 收纳层命中（优先于 bar）：抽屉展开且指针在抽屉带（窗口 y 48..92）内，
        // 按抽屉槽判定；规则与 bar 槽同构（边缘 insert / 中心 merge）
        var stowDone = false;
        if (root.stowOpenHere && wx >= 0 && wx <= winW && wy >= root.bandStowY0 && wy <= root.bandStowY1) {
            var sHit = -1;
            for (var si = 0; si < root.stowSlotItems.length; si++) {
                var ss = root.stowSlotItems[si];
                if (!ss || ss.width <= 0)
                    continue;
                var ssp = root.absPosOf(ss);
                if (wx >= ssp.x && wx <= ssp.x + ss.width && wy >= ssp.y - 4 && wy <= ssp.y + ss.height + 4) {
                    sHit = si;
                    var sfx = (wx - ssp.x) / ss.width;
                    if (sfx < 0.22) { type = "insert"; tIndex = si; sHlIndex = si; sHlMode = "insertL"; }
                    else if (sfx > 0.78) { type = "insert"; tIndex = si + 1; sHlIndex = si; sHlMode = "insertR"; }
                    else { type = "merge"; tIndex = si; sHlIndex = si; sHlMode = "merge"; }
                    break;
                }
            }
            if (sHit >= 0) {
                zone = "stow";
                stowDone = true;
            } else if (root.stowLayout.length === 0) {
                // 空抽屉：带内任意位置都是插入点 0
                type = "insert"; tIndex = 0; zone = "stow"; stowDone = true;
            } else if (root.stowSlotItems.length > 0) {
                // 抽屉间隙兜底：按槽中心定插入点（同 bar 逻辑）
                var sp2 = root.stowSlotItems.length;
                for (var sk2 = 0; sk2 < root.stowSlotItems.length; sk2++) {
                    var skk = root.stowSlotItems[sk2];
                    if (!skk)
                        continue;
                    var skp2 = root.absPosOf(skk);
                    if (wx < skp2.x + skk.width / 2) { sp2 = sk2; break; }
                }
                type = "insert"; tIndex = sp2; zone = "stow"; stowDone = true;
                if (sp2 < root.stowSlotItems.length) { sHlIndex = sp2; sHlMode = "insertL"; }
                else { sHlIndex = root.stowSlotItems.length - 1; sHlMode = "insertR"; }
            }
        }
        if (!stowDone && inBar) {
            var hit = -1;
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s || s.width <= 0)
                    continue;
                var sp = root.absPosOf(s);
                if (wx >= sp.x && wx <= sp.x + s.width && wy >= sp.y - 8 && wy <= sp.y + s.height + 8) {
                    hit = i;
                    var fx = (wx - sp.x) / s.width;
                    var slotIdsI = root.zoneLayout[i];
                    var isTraySlot = slotIdsI && slotIdsI.length === 1 && slotIdsI[0] === "tray";
                    if (isTraySlot) {
                        // tray 固定：不可被合并，命中只给左右 insert
                        if (fx < 0.5) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                        else { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    }
                    else if (fx < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fx > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(pillZone);
                if (wx >= zp.x - 10 && wx <= zp.x + pillZone.width + 10 && wy >= zp.y - 8 && wy <= zp.y + pillZone.height + 8) {
                    var p = root.slotItems.length;
                    for (var k = 0; k < root.slotItems.length; k++) {
                        var sk = root.slotItems[k];
                        if (!sk)
                            continue;
                        var skp = root.absPosOf(sk);
                        if (wx < skp.x + sk.width / 2) { p = k; break; }
                    }
                    type = "insert"; tIndex = p;
                    if (p < root.slotItems.length) { hlIndex = p; hlMode = "insertL"; }
                    else { hlIndex = root.slotItems.length - 1; hlMode = "insertR"; }
                }
            }
        }
        if (type === "insert") {
            // 插入缝定案：迟滞 + 高亮规范化（见 settleInsertSeam 注释）
            tIndex = root.settleInsertSeam(zone, tIndex, wx);
            var shl = root.seamHighlight(zone, tIndex);
            if (zone === "stow") { sHlIndex = shl[0]; sHlMode = shl[1]; }
            else { hlIndex = shl[0]; hlMode = shl[1]; }
        }
        root.dragTargetType = type;
        root.dragTargetIndex = tIndex;
        root.dragHighlightIndex = hlIndex;
        root.dragHighlightMode = hlMode;
        root.dragTargetZone = zone;
        root.dragStowHighlightIndex = sHlIndex;
        root.dragStowHighlightMode = sHlMode;
    }
    // dragEnd 统一收尾：清重入守卫 + 按抽屉的开法（UiState.stowPersistent）决定去留：
    // 持久模式（背景手势打开）→ 不预约关闭，抽屉保持打开；
    // 临时模式（起拖自动打开）→ 一律预约 300ms 后自动收起，不再看收纳集合是否变化
    // （UiState 共享计时，期间再起拖会在 pillDragStart 里取消预约）
    function finishDragEnd() {
        root.dragEnding = false;
        if (Comp.UiState.stowPersistent)
            Comp.UiState.cancelStowClose();
        else
            Comp.UiState.scheduleStowClose();
    }
    function pillDragEnd() {
        Comp.UiState.dragActive = false;
        var pid = root.dragId;
        if (pid === "")
            return;
        if (root.dragEnding) {
            console.warn("[pillzone] dragEnd reentry blocked " + pid);
            return;
        }
        root.dragEnding = true;
        var type = root.dragTargetType;
        var t = root.dragTargetIndex;
        var from = root.dragFromSlot;
        var fromZone = root.dragFromZone;
        var toZone = root.dragTargetZone;
        root.dragId = "";
        root.dragHighlightIndex = -1;
        root.dragHighlightMode = "";
        root.dragStowHighlightIndex = -1;
        root.dragStowHighlightMode = "";
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
        root.dragTargetZone = "bar";
        root.dragFromSlot = -1;
        root.dragFromZone = "bar";
        if (type === "none" || from < 0) {
            // 拖到栏外取消
            root.finishDragEnd();
            return;
        }
        // 兜底：merge 目标若是 tray 单槽，改成插到 tray 之后（Moved 已拦截，这里防漏）
        if (toZone === "bar" && type === "merge" && t >= 0 && t < root.zoneLayout.length) {
            var ts = root.zoneLayout[t];
            if (ts.length === 1 && ts[0] === "tray") {
                type = "insert";
                t = t + 1;
            }
        }
        if (type === "merge" && toZone === fromZone && t === from) {
            // 合并回自身槽位：无变化，直接收尾
            root.finishDragEnd();
            return;
        }
        // 双区提交：在 bar/stow 两份副本上摘/插，同区时下标修正规则与原单区一致，
        // 跨区时源区摘除不影响目标区下标
        var newBar = root.zoneLayout.map(function(a) { return a.slice(); });
        var newStow = root.stowLayout.map(function(a) { return a.slice(); });
        var srcLayout = fromZone === "stow" ? newStow : newBar;
        var dstLayout = toZone === "stow" ? newStow : newBar;
        var fromArr = srcLayout[from];
        if (!fromArr) {
            console.warn("[pillzone] dragEnd abort: " + pid + " slot " + from + " missing in " + fromZone);
            root.finishDragEnd();
            return;
        }
        var fix = fromArr.indexOf(pid);
        if (fix < 0) {
            console.warn("[pillzone] dragEnd abort: " + pid + " not in slot " + from);
            root.finishDragEnd();
            return;
        }
        fromArr.splice(fix, 1);
        var emptied = fromArr.length === 0;
        if (emptied)
            srcLayout.splice(from, 1);
        var shift = (emptied && fromZone === toZone && from < t) ? 1 : 0;
        if (type === "merge") {
            dstLayout[t - shift].push(pid);
        } else {
            var p = t - shift;
            if (p < 0) p = 0;
            if (p > dstLayout.length) p = dstLayout.length;
            dstLayout.splice(p, 0, [pid]);
        }
        var barChanged = JSON.stringify(newBar) !== JSON.stringify(root.zoneLayout);
        var stowChanged = JSON.stringify(newStow) !== JSON.stringify(root.stowLayout);
        // 无变化落位（把 pill 拖回自身相邻的插入线等）：给布局赋内容相同的数组
        // 不会触发 QML 变更通知，Repeater 不重建——此时绝不能先营救，
        // 否则全部 pill 滞留仓库、整区空白（已实测复现）
        if (!barChanged && !stowChanged) {
            console.warn("[pillzone] dragEnd noop " + pid);
            // 原样落位无任何变化，直接收尾
            root.finishDragEnd();
            return;
        }
        // 只营救/只赋真正变了的区（根因见 rescueAllPills 注释）：未变区赋值
        // 不发通知、Repeater 不重建，全量营救会把未变区整区吞进仓库
        root.rescueAllPills(barChanged, stowChanged);
        if (barChanged)
            root.zoneLayout = newBar;
        if (stowChanged)
            root.stowLayout = newStow;
        // 落位自检 + 自愈：先按当前模型把仍滞留仓库的 pill 确定性送回其槽
        // holder（healOrphans），再检仍失败的才打 orphan 留证
        Qt.callLater(function() {
            root.healOrphans();
            for (var oid in root.pillMap) {
                var op = root.pillMap[oid];
                if (op && op.parent === pillWarehouse)
                    console.warn("[pillzone] orphan " + oid);
            }
            // 整块归位复核：重建/营救后四块本体必须各归其位（内含块自检）
            root.applyBlockPlacement();
        });
        if (barChanged) {
            console.warn("[pillzone] layout " + JSON.stringify(newBar));
            Comp.Exec.sh("printf '%s' '" + JSON.stringify(newBar).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout.json");
        }
        if (stowChanged) {
            console.warn("[pillzone] stow " + JSON.stringify(newStow));
            Comp.Exec.sh("printf '%s' '" + JSON.stringify(newStow).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-stowed.json");
        }
        root.finishDragEnd();
    }

    // ---------- 整组拖拽（长按抓组）----------
    // Pill 长按发来 pressHeld：定位源槽，成员 <2 直接返回（Pill 侧无状态
    // 变化，回落单颗拖/点击）；≥2 才抓组并回调用 pill.beginGroupDrag() 接管
    // 本次按压（此后该 pill 的移动/松手改走 group* 信号）。
    function pillPressHeld(pill) {
        if (!pill || root.groupActive || root.dragId !== "")
            return;
        var pid = pill.pillId;
        var fromZone = "bar", from = -1;
        for (var i = 0; i < root.zoneLayout.length; i++) {
            if (root.zoneLayout[i].indexOf(pid) >= 0) { from = i; break; }
        }
        if (from < 0) {
            for (var j = 0; j < root.stowLayout.length; j++) {
                if (root.stowLayout[j].indexOf(pid) >= 0) { fromZone = "stow"; from = j; break; }
            }
        }
        if (from < 0)
            return;
        var ids = (fromZone === "stow" ? root.stowLayout : root.zoneLayout)[from].slice();
        if (ids.length < 2)
            return;
        root.groupActive = true;
        root.groupIds = ids;
        root.groupFromZone = fromZone;
        root.groupFromSlot = from;
        root.groupTargetType = "none";
        root.groupTargetIndex = -1;
        root.groupTargetZone = fromZone;
        root.groupMergeBefore = false;
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
        root.dragTargetZone = "bar";
        root.dragHighlightIndex = -1;
        root.dragHighlightMode = "";
        root.dragStowHighlightIndex = -1;
        root.dragStowHighlightMode = "";
        root.seamHystBar = -1;
        root.seamHystStow = -1;
        // 幽灵（先填内容再置 active，与 pillDragStart 同序）：宽=整组槽位宽
        // （槽 delegate 未就绪时以成员宽合计兜底），文案=成员文案空格拼接，
        // 底色/字色=组锚点（首成员）的 normalBg/normalFg，即组背景色
        var slotItem = fromZone === "stow" ? root.stowSlotItems[from] : root.slotItems[from];
        var anchor = root.pillMap[ids[0]];
        var texts = [];
        var sumW = 0;
        for (var k = 0; k < ids.length; k++) {
            var mp = root.pillMap[ids[k]];
            if (mp) { texts.push(mp.pillText); sumW += mp.animW; }
        }
        Comp.UiState.dragText = texts.join(" ");
        Comp.UiState.dragBg = anchor ? anchor.normalBg : root.theme.frameBg;
        Comp.UiState.dragFg = anchor ? anchor.normalFg : root.theme.fg;
        Comp.UiState.dragW = (slotItem && slotItem.width > 0) ? slotItem.width : Math.max(sumW + 2 * (ids.length - 1) + 4, 40);
        Comp.UiState.dragH = (slotItem && slotItem.height > 0) ? slotItem.height : 32;
        if (slotItem) {
            var sap = root.absPosOf(slotItem);
            Comp.UiState.dragX = sap.x + slotItem.width / 2;
            Comp.UiState.dragY = sap.y + 16;
        } else {
            var pap = root.absPosOf(pill);
            Comp.UiState.dragX = pap.x + pill.width / 2;
            Comp.UiState.dragY = pap.y + 16;
        }
        Comp.UiState.dragScreen = root.screenName;
        Comp.UiState.dragActive = true;
        // 抽屉双模式咬合与 pillDragStart 一致：起拖算一次拖拽开始（临时模式
        // 打开抽屉、落位后预约自动关；持久打开不降级）、取消待发自动关
        if (!(Comp.UiState.stowOpen && Comp.UiState.stowPersistent && Comp.UiState.stowScreen === root.screenName))
            Comp.UiState.stowPersistent = false;
        Comp.UiState.stowScreen = root.screenName;
        Comp.UiState.stowOpen = true;
        Comp.UiState.cancelStowClose();
        pill.beginGroupDrag();
        console.warn("[pillzone] groupGrab " + JSON.stringify(ids) + " from " + fromZone + " slot " + from);
    }
    // 命中判定与 pillDragMoved 同构（fx 0.22/0.78 边缘、中心 merge、tray 只
    // 给 insert、间隙兜底按槽中心定插入点），差异有二：merge 另记
    // groupMergeBefore（落点在目标左半 → 被拖组排在目标成员之前）；
    // 两带内未命中任何槽/间隙时按「空白落位」处理：整组作为独立槽追加到
    // 该区末尾（抽屉带全宽适用；顶栏带限本区槽位带横向范围 ±24）。
    function groupDragMoved(wx, wy) {
        if (root.vertical) { root.groupDragMovedV(wx, wy); return; }
        if (!root.groupActive)
            return;
        Comp.UiState.dragX = wx;
        Comp.UiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var zone = "bar", sHlIndex = -1, sHlMode = "";
        var gBefore = false;
        var winW = root.hostWindow ? root.hostWindow.width : 100000;
        var inBar = wx >= 0 && wx <= winW && wy >= root.bandBarY0 && wy <= root.bandBarY1;
        var stowDone = false;
        if (root.stowOpenHere && wx >= 0 && wx <= winW && wy >= root.bandStowY0 && wy <= root.bandStowY1) {
            var sHit = -1;
            for (var si = 0; si < root.stowSlotItems.length; si++) {
                var ss = root.stowSlotItems[si];
                if (!ss || ss.width <= 0)
                    continue;
                var ssp = root.absPosOf(ss);
                if (wx >= ssp.x && wx <= ssp.x + ss.width && wy >= ssp.y - 4 && wy <= ssp.y + ss.height + 4) {
                    sHit = si;
                    var sfx = (wx - ssp.x) / ss.width;
                    if (sfx < 0.22) { type = "insert"; tIndex = si; sHlIndex = si; sHlMode = "insertL"; }
                    else if (sfx > 0.78) { type = "insert"; tIndex = si + 1; sHlIndex = si; sHlMode = "insertR"; }
                    else { type = "merge"; tIndex = si; sHlIndex = si; sHlMode = "merge"; gBefore = sfx < 0.5; }
                    break;
                }
            }
            if (sHit >= 0) {
                zone = "stow";
                stowDone = true;
            } else if (root.stowLayout.length === 0) {
                type = "insert"; tIndex = 0; zone = "stow"; stowDone = true;
            } else if (root.stowSlotItems.length > 0) {
                var sp2 = root.stowSlotItems.length;
                for (var sk2 = 0; sk2 < root.stowSlotItems.length; sk2++) {
                    var skk = root.stowSlotItems[sk2];
                    if (!skk)
                        continue;
                    var skp2 = root.absPosOf(skk);
                    if (wx < skp2.x + skk.width / 2) { sp2 = sk2; break; }
                }
                type = "insert"; tIndex = sp2; zone = "stow"; stowDone = true;
                if (sp2 < root.stowSlotItems.length) { sHlIndex = sp2; sHlMode = "insertL"; }
                else { sHlIndex = root.stowSlotItems.length - 1; sHlMode = "insertR"; }
            }
        }
        if (!stowDone && inBar) {
            var hit = -1;
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s || s.width <= 0)
                    continue;
                var sp = root.absPosOf(s);
                if (wx >= sp.x && wx <= sp.x + s.width && wy >= sp.y - 8 && wy <= sp.y + s.height + 8) {
                    hit = i;
                    var fx = (wx - sp.x) / s.width;
                    var slotIdsI = root.zoneLayout[i];
                    var isTraySlot = slotIdsI && slotIdsI.length === 1 && slotIdsI[0] === "tray";
                    if (isTraySlot) {
                        if (fx < 0.5) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                        else { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    }
                    else if (fx < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fx > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; gBefore = fx < 0.5; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(pillZone);
                if (wx >= zp.x - 10 && wx <= zp.x + pillZone.width + 10 && wy >= zp.y - 8 && wy <= zp.y + pillZone.height + 8) {
                    var p = root.slotItems.length;
                    for (var k = 0; k < root.slotItems.length; k++) {
                        var sk = root.slotItems[k];
                        if (!sk)
                            continue;
                        var skp = root.absPosOf(sk);
                        if (wx < skp.x + sk.width / 2) { p = k; break; }
                    }
                    type = "insert"; tIndex = p;
                    if (p < root.slotItems.length) { hlIndex = p; hlMode = "insertL"; }
                    else { hlIndex = root.slotItems.length - 1; hlMode = "insertR"; }
                }
            }
        }
        // 空白落位：两带内仍未命中 → 整组作为独立槽追加到该区末尾
        if (type === "none") {
            if (root.stowOpenHere && wx >= 0 && wx <= winW && wy >= root.bandStowY0 && wy <= root.bandStowY1) {
                type = "insert"; tIndex = root.stowLayout.length; zone = "stow";
            } else if (wx >= 0 && wx <= winW && wy >= root.bandBarY0 && wy <= root.bandBarY1) {
                var bzp = root.absPosOf(pillZone);
                if (wx >= bzp.x - 24 && wx <= bzp.x + pillZone.width + 24) {
                    type = "insert"; tIndex = root.zoneLayout.length; zone = "bar";
                }
            }
        }
        if (type === "insert") {
            // 插入缝定案：迟滞 + 高亮规范化（见 settleInsertSeam 注释）
            tIndex = root.settleInsertSeam(zone, tIndex, wx);
            var shl = root.seamHighlight(zone, tIndex);
            if (zone === "stow") { sHlIndex = shl[0]; sHlMode = shl[1]; }
            else { hlIndex = shl[0]; hlMode = shl[1]; }
        }
        root.groupTargetType = type;
        root.groupTargetIndex = tIndex;
        root.groupTargetZone = zone;
        root.groupMergeBefore = gBefore;
        // 高亮/目标镜像到单颗的显示属性，两套 slot delegate 的 dropMode 不用改
        root.dragTargetType = type;
        root.dragTargetIndex = tIndex;
        root.dragTargetZone = zone;
        root.dragHighlightIndex = hlIndex;
        root.dragHighlightMode = hlMode;
        root.dragStowHighlightIndex = sHlIndex;
        root.dragStowHighlightMode = sHlMode;
    }
    function groupDragEnd() {
        Comp.UiState.dragActive = false;
        if (!root.groupActive)
            return;
        if (root.dragEnding) {
            console.warn("[pillzone] groupDragEnd reentry blocked");
            return;
        }
        root.dragEnding = true;
        var ids = root.groupIds;
        var from = root.groupFromSlot;
        var fromZone = root.groupFromZone;
        var type = root.groupTargetType;
        var t = root.groupTargetIndex;
        var toZone = root.groupTargetZone;
        var mergeBefore = root.groupMergeBefore;
        root.groupActive = false;
        root.groupIds = [];
        root.groupFromSlot = -1;
        root.groupFromZone = "bar";
        root.groupTargetType = "none";
        root.groupTargetIndex = -1;
        root.groupTargetZone = "bar";
        root.dragHighlightIndex = -1;
        root.dragHighlightMode = "";
        root.dragStowHighlightIndex = -1;
        root.dragStowHighlightMode = "";
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
        root.dragTargetZone = "bar";
        if (type === "none" || from < 0) {
            // 拖到两带之外取消（长按后不移动直接松手也走这里）
            root.finishDragEnd();
            return;
        }
        // 兜底：merge 目标若是 tray 单槽，改成插到 tray 之后（Moved 已拦截）
        if (toZone === "bar" && type === "merge" && t >= 0 && t < root.zoneLayout.length) {
            var ts = root.zoneLayout[t];
            if (ts.length === 1 && ts[0] === "tray") {
                type = "insert";
                t = t + 1;
            }
        }
        if (type === "merge" && toZone === fromZone && t === from) {
            // 合并回自身槽位：无变化，直接收尾
            root.finishDragEnd();
            return;
        }
        // 双区提交：源槽整槽摘除（整组恒占满一槽），目标 merge=成员拼接
        // （内部顺序各自保持，前后由 groupMergeBefore 定）、insert=整槽插入；
        // 同区摘除使目标下标 -1 的修正与单颗「源槽清空」情形一致
        var newBar = root.zoneLayout.map(function(a) { return a.slice(); });
        var newStow = root.stowLayout.map(function(a) { return a.slice(); });
        var srcLayout = fromZone === "stow" ? newStow : newBar;
        var dstLayout = toZone === "stow" ? newStow : newBar;
        var fromArr = srcLayout[from];
        if (!fromArr || JSON.stringify(fromArr) !== JSON.stringify(ids)) {
            console.warn("[pillzone] groupDragEnd abort: source slot mismatch at " + fromZone + " slot " + from);
            root.finishDragEnd();
            return;
        }
        srcLayout.splice(from, 1);
        var shift = (fromZone === toZone && from < t) ? 1 : 0;
        if (type === "merge") {
            var tgt = dstLayout[t - shift];
            if (!tgt) {
                console.warn("[pillzone] groupDragEnd abort: merge target missing");
                root.finishDragEnd();
                return;
            }
            dstLayout[t - shift] = mergeBefore ? ids.concat(tgt) : tgt.concat(ids);
        } else {
            var p = t - shift;
            if (p < 0) p = 0;
            if (p > dstLayout.length) p = dstLayout.length;
            dstLayout.splice(p, 0, ids.slice());
        }
        var barChanged = JSON.stringify(newBar) !== JSON.stringify(root.zoneLayout);
        var stowChanged = JSON.stringify(newStow) !== JSON.stringify(root.stowLayout);
        // 无变化落位同单颗纪律：不营救、直接收尾（深比较 noop）
        if (!barChanged && !stowChanged) {
            console.warn("[pillzone] groupDragEnd noop " + JSON.stringify(ids));
            root.finishDragEnd();
            return;
        }
        // 只营救/只赋真正变了的区（同 pillDragEnd，根因见 rescueAllPills 注释）
        root.rescueAllPills(barChanged, stowChanged);
        if (barChanged)
            root.zoneLayout = newBar;
        if (stowChanged)
            root.stowLayout = newStow;
        // 落位自检 + 自愈（同 pillDragEnd）：先 healOrphans 确定性归位，
        // 再检仍滞留仓库的才打 orphan 留证
        Qt.callLater(function() {
            root.healOrphans();
            for (var oid in root.pillMap) {
                var op = root.pillMap[oid];
                if (op && op.parent === pillWarehouse)
                    console.warn("[pillzone] orphan " + oid);
            }
            root.applyBlockPlacement();
        });
        if (barChanged) {
            console.warn("[pillzone] layout " + JSON.stringify(newBar));
            Comp.Exec.sh("printf '%s' '" + JSON.stringify(newBar).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout.json");
        }
        if (stowChanged) {
            console.warn("[pillzone] stow " + JSON.stringify(newStow));
            Comp.Exec.sh("printf '%s' '" + JSON.stringify(newStow).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-stowed.json");
        }
        root.finishDragEnd();
    }

    // 槽位成员的占位 holder：宽度跟随 pill.animW（显隐动画不破），拖拽中半透明示意占位
    Component {
        id: holderComponent
        Item {
            property string pillId: ""
            property var pillRef: null
            width: pillRef ? pillRef.animW : 0
            // 竖条时 holder 高跟 pill 的竖向收展（animH），横向恒 32；
            // briBox/trayBox 也有 animH（见各自定义），不会读空
            height: root.vertical ? (pillRef ? pillRef.animH : 0) : 32
            clip: true
            opacity: ((root.dragId !== "" && root.dragId === pillId) || (root.groupActive && root.groupIds.indexOf(pillId) >= 0)) ? 0.35 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
        }
    }

    // ---------- 整块拖拽（与胶囊拖拽同一套状态机语义）----------
    function attachBlockLayer(key, body, parentItem) {
        if (!body || !parentItem)
            return;
        var o = blockDragLayer.createObject(parentItem, { "blockKey": key, "bodyItem": body });
        var m = Object.assign({}, root.blockOverlays);
        m[key] = o;
        root.blockOverlays = m;
    }
    function blockGhostText(key) {
        if (key === "launcher") return Comp.Icons.launcher;
        if (key === "music") return Comp.Icons.musicPlaying;
        return "";
    }
    function blockGhostBg(key) {
        if (key === "music") return root.theme.mediaBg;
        if (key === "tray") return root.theme.accent;
        return root.theme.frameBg;
    }
    function blockDragStart(ma) {
        var key = ma.blockKey;
        var body = ma.bodyItem ? ma.bodyItem : root.blockBody(key);
        if (!body)
            return;
        // 幽灵走 shell 覆盖窗：先填内容再置 active（与 pillDragStart 同序）
        Comp.UiState.dragText = root.blockGhostText(key);
        Comp.UiState.dragBg = root.blockGhostBg(key);
        Comp.UiState.dragFg = root.theme.fg;
        Comp.UiState.dragW = Math.max(body.width, 24);
        // 横向块幽灵恒 32（与改前一致）；竖条时幽灵跟本体高（方块贴/整列）
        Comp.UiState.dragH = root.vertical ? body.height : 32;
        Comp.UiState.dragX = ma.blkLastX;
        Comp.UiState.dragY = ma.blkLastY;
        Comp.UiState.dragScreen = root.screenName;
        Comp.UiState.dragActive = true;
        // 正在操作不许抽屉被临时关闭计时收走（与 pillDragStart 一致）
        Comp.UiState.cancelStowClose();
        // 半透明示意占位：仅 opacity 无绑定的两块可做（启动器 Pill/托盘 opacity 有绑定，不动）
        if (key === "music")
            musicCluster.opacity = 0.35;
        if (key === "workspaces")
            workspacesBody.opacity = 0.35;
    }
    function blockDragEnd(ma, wx, wy) {
        if (root.vertical) { root.blockDragEndV(ma, wx, wy); return; }
        Comp.UiState.dragActive = false;
        musicCluster.opacity = 1;
        workspacesBody.opacity = 1;
        var key = ma.blockKey;
        var stowed = root.blockStowed[key];
        var winW = root.hostWindow ? root.hostWindow.width : 100000;
        var inX = wx >= 0 && wx <= winW;
        // 落位判定（窗口坐标）：在栏上拖进抽屉带（48..92）→ 收纳；
        // 在抽屉里拖回顶栏带（-12..58）→ 取出；其余原样不动
        if (!stowed && inX && wy >= root.bandStowY0 && wy <= root.bandStowY1)
            root.setBlockStowed(key, true);
        else if (stowed && inX && wy >= root.bandBarY0 && wy <= root.bandBarY1)
            root.setBlockStowed(key, false);
        // 模式联动与 finishDragEnd 一致：持久模式不关，临时模式落位后预约自动收起
        if (Comp.UiState.stowPersistent)
            Comp.UiState.cancelStowClose();
        else
            Comp.UiState.scheduleStowClose();
    }

    // 整块拖拽层：覆在块本体（或与本体同进同出的 wrapper）上。只在抽屉打开
    // （本屏）时 enabled——抽屉关着时这层等于不存在，四块照常点击使用零干扰。
    // 手势与 Pill 一致：按下记窗口坐标，位移过 8px 起拖，松手按窗口坐标落位。
    Component {
        id: blockDragLayer
        MouseArea {
            id: blkMa
            property string blockKey: ""
            property var bodyItem: null
            property bool blkDragging: false
            property real blkPressX: 0
            property real blkPressY: 0
            property real blkLastX: 0
            property real blkLastY: 0
            anchors.fill: parent
            z: 100
            enabled: root.stowOpenHere
            visible: enabled
            acceptedButtons: Qt.LeftButton
            onPressed: e => {
                // 抓住整块=正在整理：先掐掉待发的临时自动关，别拖到一半抽屉收走
                Comp.UiState.cancelStowClose();
                var ap = root.absPosOf(blkMa);
                blkPressX = ap.x + e.x;
                blkPressY = ap.y + e.y;
                blkLastX = blkPressX;
                blkLastY = blkPressY;
            }
            onPositionChanged: e => {
                if (!pressed)
                    return;
                var ap = root.absPosOf(blkMa);
                var wx = ap.x + e.x;
                var wy = ap.y + e.y;
                blkLastX = wx;
                blkLastY = wy;
                if (!blkDragging) {
                    var dx = wx - blkPressX;
                    var dy = wy - blkPressY;
                    if (dx * dx + dy * dy <= 64)
                        return;
                    blkDragging = true;
                    root.blockDragStart(blkMa);
                }
                Comp.UiState.dragX = wx;
                Comp.UiState.dragY = wy;
            }
            onReleased: {
                if (blkDragging) {
                    blkDragging = false;
                    root.blockDragEnd(blkMa, blkLastX, blkLastY);
                }
            }
            onCanceled: {
                if (blkDragging) {
                    blkDragging = false;
                    root.blockDragEnd(blkMa, blkLastX, blkLastY);
                }
            }
        }
    }

    // 抽屉里的整块 holder：壳层条带经 blockHolderDelegateRef 实例化，注册后
    // 由 applyBlockPlacement 把本体领养进来。未收纳时宽 0 不占位。
    Component {
        id: blockHolderDelegate
        Item {
            property string blockKey: modelData
            // 竖条抽屉里 holder 宽与启动器同宽（launcherPill.width）、高跟本体；横向与改前一致
            height: root.vertical ? (root.blockStowed[blockKey] ? root.blockBodyHeight(blockKey) : 0) : 32
            width: root.vertical ? (root.blockStowed[blockKey] ? launcherPill.width : 0) : (root.blockStowed[blockKey] ? root.blockBodyWidth(blockKey) : 0)
            Component.onCompleted: root.registerBlockHolder(blockKey, this)
            Component.onDestruction: root.unregisterBlockHolder(blockKey, this)
        }
    }

    // 槽位：单颗直显 pill 本人；组画共享底色 + 成员 bare 并排
    Component {
        id: slotDelegate
        Item {
            id: slot
            property var slotIds: modelData
            property var members: []
            property var anchorPill: null
            property string dropMode: root.dragHighlightIndex === index ? root.dragHighlightMode : ""
            property bool anyShown: {
                for (var i = 0; i < members.length; i++)
                    if (members[i].shown)
                        return true;
                return false;
            }
            // 竖条时槽位尺寸轴互换：高 = 成员 animH 之和（组 +2 上下边），
            // 宽 = 成员 animW 最大值（组与单槽同宽，无左右边）；横向与改前一致
            height: root.vertical ? (function() {
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animH;
                if (members.length >= 2)
                    return anyShown ? s + 1 * (members.length - 1) + 2 : 0;
                return members.length === 1 ? s : 0;
            })() : 32
            width: {
                if (root.vertical) {
                    var m = 0;
                    for (var i = 0; i < members.length; i++)
                        if (members[i].animW > m)
                            m = members[i].animW;
                    if (members.length >= 2)
                        return anyShown ? m : 0;
                    return m;
                }
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animW;
                if (members.length >= 2)
                    return anyShown ? s + 2 * (members.length - 1) + 4 : 0;
                return members.length === 1 ? s : 0;
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                visible: slot.slotIds.length >= 2 && slot.anyShown
                color: slot.anchorPill ? slot.anchorPill.normalBg : "transparent"
            }
            Row {
                id: slotRow
                anchors { left: parent.left; leftMargin: slot.slotIds.length >= 2 ? 2 : 0; verticalCenter: parent.verticalCenter }
                spacing: 2
                height: 32
                visible: !root.vertical
            }
            Column {
                id: slotCol
                anchors { left: parent.left; leftMargin: 0; top: parent.top; topMargin: slot.slotIds.length >= 2 ? 1 : 0 }
                spacing: 1
                visible: root.vertical
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.width: 2
                border.color: root.theme.clockBg
                visible: slot.dropMode === "merge"
                z: 5
            }
            Rectangle {
                width: root.vertical ? parent.width : 2; height: root.vertical ? 2 : 32
                x: root.vertical ? 0 : -2; y: root.vertical ? -2 : 0
                color: root.theme.clockBg
                visible: slot.dropMode === "insertL"
                z: 5
            }
            Rectangle {
                width: root.vertical ? parent.width : 2; height: root.vertical ? 2 : 32
                x: root.vertical ? 0 : parent.width; y: root.vertical ? parent.height : 0
                color: root.theme.clockBg
                visible: slot.dropMode === "insertR"
                z: 5
            }

            Component.onCompleted: {
                var ms = [];
                var isGroup = slotIds.length >= 2;
                for (var i = 0; i < slotIds.length; i++) {
                    var pill = root.pillMap[slotIds[i]];
                    if (!pill)
                        continue;
                    var holder = holderComponent.createObject(root.vertical ? slotCol : slotRow, { "pillId": slotIds[i], "pillRef": pill });
                    if (slotIds[i] === "tray") {
                        // 托盘槽位语义不动：holder 仍是它的家并登记归位点；
                        // 但整块收纳中时本体留在抽屉，不从抽屉抢回来（animW 已归 0
                        // 让本 holder 落空），只登记成员
                        root.trayHolder = holder;
                        if (root.blockStowed.tray) {
                            // 整块收纳中的托盘不是抽屉胶囊：模式恒为 bar，
                            // 只登记成员（哑属性，防 Cannot assign 中断完成）
                            pill.drawerMode = false;
                            pill.vertical = root.vertical;
                            ms.push(pill);
                            continue;
                        }
                    }
                    pill.parent = holder;
                    pill.x = 0;
                    pill.y = 0;
                    pill.bare = isGroup;
                    pill.drawerMode = false;
                    pill.vertical = root.vertical;
                    ms.push(pill);
                }
                slot.members = ms;
                slot.anchorPill = ms.length > 0 ? ms[0] : null;
                if (isGroup && ms.length > 0) {
                    var ap = ms[0];
                    for (var k = 0; k < ms.length; k++) {
                        (function(p) {
                            p.bareFg = Qt.binding(function() { return ap.normalFg; });
                        })(ms[k]);
                    }
                }
                root.registerSlot(index, slot);
                root.applyBlockPlacement();
            }
            Component.onDestruction: {
                for (var i = 0; i < members.length; i++) {
                    // 归属守卫（父链判定）：成员的 parent 是本 slot 为它建的 holder
                    // 时才归本 slot 所有；已被新 delegate 领养（parent 换成新 holder）
                    // 或已被 rescueAllPills 送回仓库的，父链已变，一律不碰——
                    // 否则旧 delegate 销毁会把新槽位里的 pill 拽回仓库变空白
                    var mp = members[i].parent;
                    if (!mp || (mp.parent !== slotRow && mp.parent !== slotCol))
                        continue;
                    members[i].bare = false;
                    members[i].drawerMode = false;
                    members[i].vertical = false;
                    members[i].parent = pillWarehouse;
                }
                root.unregisterSlot(index, slot);
            }
        }
    }

    // 收纳槽位：与 slotDelegate 同构（领养/组背景/命中高亮），差异仅在
    // 注册表走 stowSlotItems、高亮读 dragStowHighlight* 且须 dragTargetZone=stow
    Component {
        id: stowSlotDelegate
        Item {
            id: slot
            property var slotIds: modelData
            property var members: []
            property var anchorPill: null
            property string dropMode: (root.dragTargetZone === "stow" && root.dragStowHighlightIndex === index) ? root.dragStowHighlightMode : ""
            property bool anyShown: {
                for (var i = 0; i < members.length; i++)
                    if (members[i].shown)
                        return true;
                return false;
            }
            // 竖条时槽位尺寸轴互换：高 = 成员 animH 之和（组 +2 上下边），
            // 宽 = 成员 animW 最大值（组与单槽同宽，无左右边）；横向与改前一致
            height: root.vertical ? (function() {
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animH;
                if (members.length >= 2)
                    return anyShown ? s + 1 * (members.length - 1) + 2 : 0;
                return members.length === 1 ? s : 0;
            })() : 32
            width: {
                if (root.vertical) {
                    var m = 0;
                    for (var i = 0; i < members.length; i++)
                        if (members[i].animW > m)
                            m = members[i].animW;
                    if (members.length >= 2)
                        return anyShown ? m : 0;
                    return m;
                }
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animW;
                if (members.length >= 2)
                    return anyShown ? s + 2 * (members.length - 1) + 4 : 0;
                return members.length === 1 ? s : 0;
            }

            Rectangle {
                anchors.fill: parent
                radius: 10
                visible: slot.slotIds.length >= 2 && slot.anyShown
                color: slot.anchorPill ? slot.anchorPill.normalBg : "transparent"
            }
            Row {
                id: slotRow
                anchors { left: parent.left; leftMargin: slot.slotIds.length >= 2 ? 2 : 0; verticalCenter: parent.verticalCenter }
                spacing: 2
                height: 32
                visible: !root.vertical
            }
            Column {
                id: slotCol
                anchors { left: parent.left; leftMargin: 0; top: parent.top; topMargin: slot.slotIds.length >= 2 ? 1 : 0 }
                spacing: 1
                visible: root.vertical
            }
            Rectangle {
                anchors.fill: parent
                radius: 10
                color: "transparent"
                border.width: 2
                border.color: root.theme.clockBg
                visible: slot.dropMode === "merge"
                z: 5
            }
            Rectangle {
                width: root.vertical ? parent.width : 2; height: root.vertical ? 2 : 32
                x: root.vertical ? 0 : -2; y: root.vertical ? -2 : 0
                color: root.theme.clockBg
                visible: slot.dropMode === "insertL"
                z: 5
            }
            Rectangle {
                width: root.vertical ? parent.width : 2; height: root.vertical ? 2 : 32
                x: root.vertical ? 0 : parent.width; y: root.vertical ? parent.height : 0
                color: root.theme.clockBg
                visible: slot.dropMode === "insertR"
                z: 5
            }

            Component.onCompleted: {
                var ms = [];
                var isGroup = slotIds.length >= 2;
                for (var i = 0; i < slotIds.length; i++) {
                    var pill = root.pillMap[slotIds[i]];
                    if (!pill)
                        continue;
                    var holder = holderComponent.createObject(root.vertical ? slotCol : slotRow, { "pillId": slotIds[i], "pillRef": pill });
                    pill.parent = holder;
                    pill.x = 0;
                    pill.y = 0;
                    pill.bare = isGroup;
                    // 抽屉槽领养：切抽屉模式，显示「图标 + 中文名」
                    pill.drawerMode = true;
                    pill.vertical = root.vertical;
                    ms.push(pill);
                }
                slot.members = ms;
                slot.anchorPill = ms.length > 0 ? ms[0] : null;
                if (isGroup && ms.length > 0) {
                    var ap = ms[0];
                    for (var k = 0; k < ms.length; k++) {
                        (function(p) {
                            p.bareFg = Qt.binding(function() { return ap.normalFg; });
                        })(ms[k]);
                    }
                }
                root.registerStowSlot(index, slot);
            }
            Component.onDestruction: {
                for (var i = 0; i < members.length; i++) {
                    // 归属守卫同 slotDelegate：父链不属于本槽的一律不碰
                    var mp = members[i].parent;
                    if (!mp || (mp.parent !== slotRow && mp.parent !== slotCol))
                        continue;
                    members[i].bare = false;
                    members[i].drawerMode = false;
                    members[i].vertical = false;
                    members[i].parent = pillWarehouse;
                }
                root.unregisterStowSlot(index, slot);
            }
        }
    }

    // 显隐开关走 BarState 单相位（flag 与文本同一次产出，动画单波齐出）

    // ---------- 左组 ----------
    // 启动器（整块收纳单位）：wrapper 常驻占位，本体在 wrapper 与抽屉 holder
    // 之间搬；收纳时 wrapper 宽 0 不留洞
    Item {
        id: launcherWrap
        Layout.preferredWidth: root.blockStowed.launcher ? 0 : launcherPill.width
        Layout.preferredHeight: root.vertical ? launcherPill.height : 32
        Layout.alignment: Qt.AlignHCenter
        Comp.Pill {
            id: launcherPill
            normalBg: theme.frameBg; normalFg: theme.fg
            pillText: Comp.Icons.launcher; textSize: 14; fixedWidth: 34.8 // 宽与图标解耦：14px 徽标仍占 34.8 外框
            clickLeft: "rofi -show drun"
            clickRight: "bash " + Comp.Exec.commonDir + "/toggle-left.sh"
        }
    }
    // 工作区（整块收纳单位）：本体高 24，靠 verticalCenter 锚在 32 的家里居中
    // （与原先在 RowLayout 里被居中的位置一致），归位逻辑不碰它的 y
    Item {
        id: workspacesWrap
        Layout.preferredWidth: root.blockStowed.workspaces ? 0 : (root.vertical ? Comp.UiState.tileW : workspacesBody.implicitWidth)
        Layout.preferredHeight: root.vertical ? workspacesBody.implicitHeight : 32
        Layout.alignment: Qt.AlignHCenter
        BarMod.Workspaces {
            id: workspacesBody
            theme: root.theme; screenName: root.screenName
            vertical: root.vertical
            anchors.verticalCenter: parent.verticalCenter
            anchors.horizontalCenter: parent.horizontalCenter
        }
    }

    // 左侧工具组：8 图标合并到一个胶囊（录制/截图/取色/剪贴板/护眼/主题/壁纸/显示器）
    Comp.ToolsGroup {
        id: toolsGroup
        Layout.alignment: Qt.AlignHCenter
        theme: root.theme
        screenName: root.screenName
        hostWindow: root.hostWindow
        forceHidden: Comp.BarState.flagL
        barState: Comp.BarState
        exec: Comp.Exec
        uiState: Comp.UiState
        icons: Comp.Icons
    }

    // 音乐簇（整块收纳单位）：歌名+音律+歌词三件先包进一个 RowLayout 容器再
    // 整块搬——容器必须是 RowLayout：MusicInfo/音律/歌词都靠 Layout 宽度收放
    //（animW/forceHidden 的折叠语义），内部 BarState flagM/flagT 逻辑原样不动。
    // 簇内 spacing 2 与栏 RowLayout 的 spacing 2 相同，外观衔接不变。
    Item {
        id: musicWrap
        Layout.preferredWidth: root.blockStowed.music ? 0 : musicCluster.implicitWidth
        Layout.preferredHeight: root.vertical ? musicCluster.implicitHeight : 32
        Layout.alignment: Qt.AlignHCenter
        RowLayout {
            id: musicCluster
            spacing: 2
            // 媒体组（原生 Mpris，语义与 music.py / mpris 控制一致）
            Comp.MusicInfo {
                normalBg: theme.mediaBg; normalFg: theme.fg
                theme: root.theme; screenName: root.screenName
                vertical: root.vertical
                // 右键：音乐总开关，隐藏音律+歌词（与歌词右键一致）
                onRightClicked: {
                    Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music.sh");
                    Comp.BarState.refresh();
                }
            }
            BarMod.LevelMeter { theme: root.theme; screenName: root.screenName; vertical: root.vertical }
            Comp.Pill {
                normalBg: theme.mediaBg; normalFg: theme.fg
                pillText: Comp.BarState.lyricT
                // 音乐组跟随者：总闸或尾闸拉下都折叠（开关位在歌名/音律右键）；
                // 竖条时歌词也收起，簇里只剩封面+播放方块
                forceHidden: Comp.BarState.flagM || Comp.BarState.flagT || root.vertical
                // 右键：音乐总开关（与歌名右键一致，含音律），点后即时补刷
                onRightClicked: {
                    Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music.sh");
                    Comp.BarState.refresh();
                }
            }
        }
    }

    Item {
        id: barSpacer
        Layout.fillWidth: true
        Layout.fillHeight: true // 竖条时吸掉全部余高：上区（左源模块）贴顶、下区（右源模块）贴底；横向与改前一致
        Layout.alignment: Qt.AlignHCenter
        // 字形预热文本挂在这里：Item 的孩子不参与 RowLayout 排布
        // （之前直接放 Bar 里，implicitWidth 巨大把整栏顶偏），
        // 但仍会渲染，保证图标字形首帧前传好。
        Text {
            width: 1; height: 1
            opacity: 0.01
            clip: true
            font.family: theme.fontFamily
            font.pixelSize: 14
            text: Comp.Icons.launcher + Comp.Icons.power
                + Comp.Icons.musicPlaying + Comp.Icons.musicPaused
                + Comp.Icons.prev + Comp.Icons.play + Comp.Icons.pause + Comp.Icons.next
                + Comp.Icons.shuffle + Comp.Icons.loopOff + Comp.Icons.loopAll + Comp.Icons.loopOne
                + Comp.Icons.volMute + Comp.Icons.vol0 + Comp.Icons.volLow + Comp.Icons.volHigh
                + Comp.Icons.briLow + Comp.Icons.briMid + Comp.Icons.briHigh
                + Comp.Icons.cpu + Comp.Icons.mem + Comp.Icons.net
                + Comp.Icons.btOn + Comp.Icons.btOff
                + Comp.Icons.bat0 + Comp.Icons.bat1 + Comp.Icons.bat2 + Comp.Icons.bat3 + Comp.Icons.bat4
                + Comp.Icons.batCharging + Comp.Icons.coverFallback
        }
        // 拖拽幽灵已移交 shell 层覆盖窗（UiState.drag* 状态驱动），栏内不再绘制
    }

    // ---------- 右组 ----------
    // 胶囊仓库：右侧全部胶囊声明停在这里（隐藏不排版），由 pillZone 槽位按
    // zoneLayout 领养渲染。声明内部绑定与原来一字未改，只加 id/pillId/
    // dragEnabled 与拖拽信号连接（tray 是内联 Rectangle 不是 Pill 家族，
    // 不加拖拽、只被领养占位）。亮度两颗装进 briBox 逻辑槽（见下）。
    Item {
        id: pillWarehouse
        visible: false
        width: 0
        height: 0
        Layout.preferredWidth: 0
        Layout.preferredHeight: 0

        Comp.ScriptPill {
            id: updatesPill
            pillId: "updates"
            dragEnabled: true
            baseBg: theme.accent; baseFg: theme.fg; hiBg: theme.clockBg; hiFg: theme.clockFg
            execCmd: Comp.Exec.commonDir + "/check-updates.sh"
            pollInterval: 3600000
            clickLeft: "kitty --hold sh -c 'sudo dnf upgrade'"
            clickRight: "pkill -RTMIN+8 waybar"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.ScriptPill {
            id: weatherPill
            pillId: "weather"
            dragEnabled: true
            baseBg: theme.accent; baseFg: theme.fg
            anchorKey: "weatherAnchorX"
            anchorScreen: root.screenName
            execCmd: Comp.Exec.commonDir + "/weather.py"
            pollInterval: 1800000
            // 左键开/关天气下拉面板（原 kitty wttr.in 让位给面板，数据同源 weather.json）
            onLeftClicked: Comp.UiState.toggleWeather(root.screenName)
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.AudioPill {
            id: audioPill
            pillId: "audio"
            dragEnabled: true
            baseBg: theme.deviceBg; baseFg: theme.fg
            screenName: root.screenName
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 亮度逻辑槽：内接屏亮度走共享聚合；外接屏 ddc 太慢，独立 ScriptPill 保留。
        // 两块互斥显示（forceHidden），同报一个 briAnchorX（隐藏的不上报）。
        // briBox 本体被槽位领养：animW 取两颗较大值（任一时刻只有一颗可见），
        // pillText/normalBg/normalFg 转发可见的那颗，供幽灵与组背景读取；
        // 两颗 pillId 同为 "bri"，隐藏的那颗没面积自然抓不到。
        Item {
            id: briBox
            height: vertical ? animH : 32
            // 与 Pill 对齐的哑属性：槽位领养/营救会统一写 bare、组内统一绑 bareFg，
            // 缺了会报 Cannot assign 并中断 delegate 的 onCompleted（成员登记失效变空白）
            property bool bare: false
            property color bareFg: normalFg
            // 同上哑属性：领养会统一写 drawerMode；内两颗 pill 的 drawerMode
            // 绑到这里（delegate 只领养 briBox 本体，不碰内 pill），抽屉里
            // 亮度显示「图标 + 亮度」而非实时百分比。
            property bool drawerMode: false
            // 竖条透传给内两颗 pill（与 drawerMode 同款绑定）；animH 取
            // 可见那颗的竖向收展，竖条时盒高跟它走
            property bool vertical: false
            property real animW: Math.max(briIntPill.animW, briExtPill.animW)
            property real animH: Math.max(briIntPill.animH, briExtPill.animH)
            width: animW
            property bool shown: briIntPill.shown || briExtPill.shown
            property string pillText: root.isExternal ? briExtPill.pillText : briIntPill.pillText
            property color normalBg: theme.deviceBg
            property color normalFg: theme.fg

            Comp.Pill {
                id: briIntPill
                pillId: "bri"
                drawerMode: briBox.drawerMode
                vertical: briBox.vertical
                dragEnabled: true
                normalBg: theme.deviceBg; normalFg: theme.fg
                anchorKey: "briAnchorX"
                anchorScreen: root.screenName
                forceHidden: root.isExternal
                pillText: Comp.BarState.briT
                scrollUpCmd: Comp.Exec.scriptDir + "/brightness.sh up"
                scrollDownCmd: Comp.Exec.scriptDir + "/brightness.sh down"
                clickRight: Comp.Exec.scriptDir + "/brightness.sh mid"
                onLeftClicked: { Comp.UiState.toggleBri(root.screenName, root.isExternal); Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh"); }
                onRightClicked: Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh")
                onScrollUp: Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh")
                onScrollDown: Comp.BarState.refreshOne("bri", "bash " + Comp.Exec.scriptDir + "/brightness.sh")
                onDragStarted: pid => root.pillDragStart(pid)
                onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
                onDragEnded: root.pillDragEnd()
            }
            Comp.ScriptPill {
                id: briExtPill
                pillId: "bri"
                drawerMode: briBox.drawerMode
                vertical: briBox.vertical
                dragEnabled: true
                baseBg: theme.deviceBg; baseFg: theme.fg
                anchorKey: "briAnchorX"
                anchorScreen: root.screenName
                forceHidden: !root.isExternal
                execCmd: "bash " + Comp.Exec.scriptDir + "/brightness-external.sh"
                pollInterval: 30000
                scrollUpCmd: "ddcutil setvcp 10 + 5"
                scrollDownCmd: "ddcutil setvcp 10 - 5"
                clickRight: "ddcutil setvcp 10 50"
                onLeftClicked: Comp.UiState.toggleBri(root.screenName, root.isExternal)
                onDragStarted: pid => root.pillDragStart(pid)
                onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
                onDragEnded: root.pillDragEnd()
            }
        }
        Comp.Pill {
            id: cpuPill
            pillId: "cpu"
            dragEnabled: true
            normalBg: theme.sysmonBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            pillText: Comp.BarState.cpuT
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: ppPill
            pillId: "pp"
            dragEnabled: true
            normalFg: (Comp.BarState.ppC === "recording" || Comp.BarState.ppC === "kernel" || Comp.BarState.ppC === "many" || Comp.BarState.ppC === "inhibited") ? theme.clockFg : theme.fg
            normalBg: (Comp.BarState.ppC === "recording" || Comp.BarState.ppC === "kernel" || Comp.BarState.ppC === "many" || Comp.BarState.ppC === "inhibited") ? theme.clockBg : theme.sysmonBg
            pillText: Comp.BarState.ppT
            clickLeft: Comp.Exec.commonDir + "/powerprofiles.sh toggle"
            onLeftClicked: Comp.BarState.refreshOne("pp", Comp.Exec.commonDir + "/powerprofiles.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: memPill
            pillId: "mem"
            dragEnabled: true
            normalBg: theme.sysmonBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            pillText: Comp.BarState.memT
            clickLeft: "kitty --title 'System Monitor' btop"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: netPill
            pillId: "net"
            dragEnabled: true
            normalBg: theme.deviceBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            pillText: Comp.BarState.netT
            clickLeft: "kitty -e nmtui"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.BluetoothPill {
            id: btPill
            pillId: "bt"
            dragEnabled: true
            normalBg: theme.deviceBg; normalFg: theme.fg
            forceHidden: Comp.BarState.flagS
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.BatteryPill {
            id: batPill
            pillId: "bat"
            dragEnabled: true
            normalBg: theme.sysmonBg; normalFg: theme.fg
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 时钟：反色锚点
        Comp.Pill {
            id: clockPill
            pillId: "clock"
            dragEnabled: true
            normalBg: theme.clockBg; normalFg: theme.clockFg; bold: true
            pillText: Qt.formatDateTime(clockDate, "hh:mm")
            property var clockDate: new Date()
            Timer { interval: 1000; running: !clockPill.frozen; repeat: true; onTriggered: clockPill.clockDate = new Date() }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 通知铃：未读数 + 开关历史中心。无通知时用 0 占位，宽度恒定，浮窗不跳。
        // anchorKey 上报中心横坐标，toast 栈与通知中心都锚到铃铛下方
        //（缺了它 notifAnchorX 恒为 0，toast 窗会被摆到屏外——2026-09 实测）。
        Comp.Pill {
            id: bellPill
            pillId: "bell"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            anchorKey: "notifAnchorX"
            anchorScreen: root.screenName
            pillText: Comp.Icons.bell + " " + Comp.Notifs.unread
            onLeftClicked: {
                Comp.Notifs.markRead();
                Comp.UiState.toggleNotif(root.screenName);
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 托盘：与其他模块一致的圆角色块底。
        // 注意：items 是 UntypedObjectModel，没有 .count，Repeater 直接吃它也没有
        // modelData；一律走 .values（JS 数组），和 Mpris 用法一致。
        Rectangle {
            id: trayBox
            // 同 briBox：槽位领养/营救统一写 bare，缺属性会中断 delegate 完成
            property bool bare: false
            // 同上哑属性：托盘是整块收纳单位、永不进抽屉胶囊槽，drawerMode
            // 恒为 false；缺了营救/自愈写它会报 Cannot assign 中断函数
            property bool drawerMode: false
            // 竖条时托盘竖排（图标列），宽与启动器同宽、高跟图标列；
            // 菜单改向屏内弹（左栏向右、右栏向左），横向仍向下弹
            property bool vertical: false
            // 整块收纳中时 animW 归 0：bar 槽位 holder 落空、不占栏上位置（本体在抽屉里）
            property real animW: (SystemTray.items.values.length > 0 && !root.blockStowed.tray) ? (root.vertical ? launcherPill.width : trayRow.implicitWidth + 12) : 0
            property real animH: (SystemTray.items.values.length > 0 && !root.blockStowed.tray) ? (root.vertical ? trayCol.implicitHeight + 8 : 32) : 0
            // shell 单引号转义（歌名里什么引号都有）
            function shQ(s) {
                return "'" + String(s || "").replace(/'/g, "'\\''") + "'";
            }

            Behavior on animW { enabled: Comp.UiState.animReady; NumberAnimation { duration: 200; easing.type: Easing.InOutQuad } }
            Behavior on opacity { enabled: Comp.UiState.animReady; NumberAnimation { duration: 150; easing.type: Easing.OutQuad } }

            visible: opacity > 0.01
            opacity: SystemTray.items.values.length > 0 ? 1 : 0
            height: root.vertical ? trayCol.implicitHeight + 8 : 32
            width: root.vertical ? launcherPill.width : trayRow.implicitWidth + 12
            Layout.preferredWidth: animW
            Layout.preferredHeight: root.vertical ? animH : 32
            radius: 10
            clip: true
            color: theme.accent

            Row {
                id: trayRow
                anchors.centerIn: parent
                spacing: 4
                visible: !root.vertical
                Repeater {
                    model: root.vertical ? [] : SystemTray.items.values
                    delegate: trayCell
                }
            }
            Column {
                id: trayCol
                anchors.centerIn: parent
                spacing: 2
                visible: root.vertical
                Repeater {
                    model: root.vertical ? SystemTray.items.values : []
                    delegate: trayCell
                }
            }
            Component {
                id: trayCell
                MouseArea {
                    id: trayMouse
                    width: 24; height: root.vertical ? 24 : 32
                    // 列内容器里横向居中；横向 Row 里必须清掉——本构建不会忽略
                    // 布局方向上的锚，挂上后 cell 会脱离顺序排布、全叠在 Row
                    // 中心，且不再计入 Row 隐含宽度，托盘槽会被压成一条缝
                    // （2026-11-05 顶栏重叠的根因，与工作区圆点同案）。
                    anchors.horizontalCenter: root.vertical ? parent.horizontalCenter : undefined
                        acceptedButtons: Qt.LeftButton | Qt.RightButton
                        // 左键通用链（零应用名）：onlyMenu 出菜单，否则走 tray-open.py——
                        // 模糊找窗聚焦（已聚焦跳过）→ 调 Activate（缺失则报错）→
                        // 触发菜单显示项 → SecondaryActivate。右键一律菜单优先。
                        onClicked: e => {
                            if (e.button === Qt.LeftButton) {
                                if (modelData.onlyMenu && modelData.hasMenu) {
                                    trayMenu.open();
                                } else {
                                    Comp.Exec.sh("python3 " + Comp.Exec.commonDir + "/tray-open.py " + trayBox.shQ(modelData.id) + " " + trayBox.shQ(modelData.title) + " " + trayBox.shQ(modelData.tooltipTitle));
                                }
                            } else {
                                if (modelData.hasMenu)
                                    trayMenu.open();
                                else
                                    modelData.secondaryActivate();
                            }
                        }
                        // 右键菜单：很多 SNI 不实现 SecondaryActivate，
                        // 必须走 DBusMenu；anchor.window 复用顶栏窗口
                        QsMenuAnchor {
                            id: trayMenu
                            anchor.window: root.hostWindow
                            anchor.item: trayMouse
                            anchor.edges: root.vertical ? (root.barLeft ? Edges.Right : Edges.Left) : Edges.Bottom
                            anchor.gravity: root.vertical ? (root.barLeft ? Edges.Right : Edges.Left) : Edges.Bottom
                            menu: modelData.menu
                        }
                        // 模拟原图标样式统一绘制：映射到就画 TrayDraw（Canvas 按原图标形状画，
                        // 颜色跟主题 fg/条带底色，壁纸换色跟着变），未映射仍用 IconImage 播原图。
                        // tray 图标可能是主题名也可能是路径，原图分支必须用 IconImage，
                        // 普通 Image 播不了主题名会导致整块空白。
                        Comp.TrayDraw {
                            id: trayDraw
                            anchors.centerIn: parent
                            trayId: modelData.id
                            trayTitle: modelData.title
                            trayIcon: modelData.icon
                            drawColor: theme.fg
                            bgColor: theme.accent
                            // 输入法中/英跟输入法胶囊同一来源（fcitx_status.sh）
                            fcitxLang: fcitxPill.pillText
                        }
                        IconImage {
                            anchors.centerIn: parent
                            implicitSize: 20
                            visible: trayDraw.drawKey === ""
                            source: modelData.icon
                        }
                    }
                }
            }
        Comp.ScriptPill {
            id: fcitxPill
            pillId: "fcitx"
            dragEnabled: true
            baseBg: theme.accent; baseFg: theme.fg
            execCmd: Comp.Exec.commonDir + "/fcitx_status.sh"
            pollInterval: 1000
            clickLeft: "fcitx5-remote -s"
            clickRight: "fcitx5-configtool"
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: inhibitPill
            pillId: "inhibit"
            dragEnabled: true
            normalBg: (Comp.BarState.inhibitC === "recording" || Comp.BarState.inhibitC === "kernel" || Comp.BarState.inhibitC === "many" || Comp.BarState.inhibitC === "inhibited") ? theme.clockBg : theme.accent
            normalFg: (Comp.BarState.inhibitC === "recording" || Comp.BarState.inhibitC === "kernel" || Comp.BarState.inhibitC === "many" || Comp.BarState.inhibitC === "inhibited") ? theme.clockFg : theme.fg
            pillText: Comp.BarState.inhibitT
            clickLeft: "bash " + Comp.Exec.commonDir + "/inhibit.sh toggle"
            onLeftClicked: Comp.BarState.refreshOne("inhibit", "bash " + Comp.Exec.scriptDir + "/inhibit.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: ccPill
            pillId: "cc"
            dragEnabled: true
            normalBg: theme.frameBg; normalFg: theme.fg
            anchorKey: "ccAnchorX"
            anchorScreen: root.screenName
            pillText: Comp.Icons.sliders
            textSize: 14
            onLeftClicked: Comp.UiState.toggleSidebar(root.screenName)
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        Comp.Pill {
            id: powerPill
            pillId: "power"
            dragEnabled: true
            normalBg: theme.frameBg; normalFg: theme.fg
            pillText: Comp.Icons.power
            clickLeft: "~/.config/rofi/scripts/powermenu.sh"
            clickRight: "bash " + Comp.Exec.commonDir + "/toggle-system.sh"
            onRightClicked: Comp.BarState.refresh()
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
    }
    // 天气缓存（--fetch/唤醒预热）一落地就补刷，不等 30 分钟轮询；
    // 前台 exec 从不写盘，不会自激循环
    FileView {
        path: Quickshell.env("HOME") + "/.cache/by-mgr/weather.json"
        watchChanges: true
        onFileChanged: weatherPill.refresh()
    }
    // 胶囊区：按 zoneLayout 渲染槽位（单颗/组合），槽位 delegate 在文件上方 slotDelegate
    Row {
        id: pillZone
        spacing: 2
        height: 32
        Layout.alignment: Qt.AlignHCenter
        Repeater {
            model: root.zoneReady && !root.vertical ? root.zoneLayout : []
            delegate: slotDelegate
        }
    }
    // 竖条胶囊区：与横向同模型、双 Repeater 切模型（只一个有 delegate，
    // 切换时旧 delegate 销毁送仓库、新 delegate 领养，与既有重建路径一致）
    Column {
        id: pillZoneV
        spacing: 1
        visible: false
        Layout.alignment: Qt.AlignHCenter
        Repeater {
            model: root.zoneReady && root.vertical ? root.zoneLayout : []
            delegate: slotDelegate
        }
    }
}
