import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// 左侧工具组：8 件工具（录制/截图/取色/剪贴板/护眼/主题/壁纸/显示器）改为独立胶囊，
// 不再共用一个托盘；拖拽组合/分离与右侧胶囊区同构（zoneLayout + 仓库领养，
// 幽灵走 UiState 全局覆盖窗），分组存 ~/.cache/by-mgr/qs-bar-layout-left.json，重启恢复。
Item {
    id: root
    property var theme
    property string screenName
    property bool forceHidden: false
    property var barState
    property var exec
    property var uiState
    property var icons

    // 竖条方向（由 Bar 透传的 uiState 读，与 Bar 右区同源）；hostWindow
    // 由 Bar 传入，供竖条拖拽带区换算（右栏镜像要窗宽）
    property bool vertical: root.uiState ? root.uiState.barVertical : false
    property bool barLeft: root.uiState ? root.uiState.barDirection === "left" : false
    property var hostWindow: null
    visible: !forceHidden
    Layout.preferredWidth: visible ? (vertical ? toolZoneV.implicitWidth : toolZone.implicitWidth) : 0
    Layout.preferredHeight: vertical ? toolZoneV.implicitHeight : 32
    height: vertical ? toolZoneV.implicitHeight : 32
    implicitWidth: vertical ? toolZoneV.implicitWidth : toolZone.implicitWidth
    implicitHeight: vertical ? toolZoneV.implicitHeight : 32

    // ---------- 工具胶囊拖拽区（移植自 Bar.qml pillZone，机制同构）----------
    // zoneLayout = 有序槽位表，槽位是 id 数组：单元素 = 单颗，多元素 = 组合胶囊。
    property var pillMap: ({})
    property var defaultZoneLayout: [["rec"], ["shot"], ["pick"], ["clip"], ["gamma"], ["theme"], ["wall"], ["screen"]]
    property var zoneLayout: defaultZoneLayout
    property bool zoneReady: false

    // 拖拽命中带区（窗口坐标）：与 Bar 右区同构，bottom 时镜像（见 Bar 注释）
    property bool barBottom: root.uiState ? root.uiState.barDirection === "bottom" : false
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

    // ---------- 整组拖拽（长按抓组，与单颗 pillDrag 并行，与 Bar.qml 同构）----------
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

    // ---------- 收纳抽屉（左区）----------
    // stowLayout = 已收纳槽位表（与 zoneLayout 同构），单独存 qs-bar-layout-stowed-left.json。
    // 校验与 Bar.qml 右区同构：zoneLayout ∪ stowLayout 恰覆盖 8 id 各一次才采用，
    // 不合法回退默认 8 单颗 + 收纳空。抽屉宿主在 shell.qml 顶栏窗内，经 Bar 的
    // toolsGroupRef 读本组件的 stowLayout / stowDelegateRef 渲染。
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
    property var stowDelegateRef: stowSlotDelegate
    // 本屏抽屉是否展开（UiState 按屏分键）
    property bool stowOpenHere: root.uiState ? (root.uiState.stowOpen && root.uiState.stowScreen === root.screenName) : false

    FileView {
        id: layoutLeftFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-layout-left.json"
        // 定案后本实例的实时模型即归属真源：watcher 回读（含自己写盘的
        // 回声、另一屏实例的写盘）一律忽略，文件只在启动定案前读
        // （与 Bar.qml 右区同构，2026-10-22 竞态收尾）
        onLoaded: { if (root.layoutsFinalized) return; root.applyLayoutFile(text()); root.barFileSettled = true; root.maybeFinalizeLayouts(false); }
        onLoadFailed: { if (root.layoutsFinalized) return; root.barFileSettled = true; root.maybeFinalizeLayouts(false); }
    }
    FileView {
        id: stowLeftFile
        path: Quickshell.env("HOME") + "/.cache/by-mgr/qs-bar-layout-stowed-left.json"
        onLoaded: { if (root.layoutsFinalized) return; root.applyStowFile(text()); root.stowFileSettled = true; root.maybeFinalizeLayouts(false); }
        onLoadFailed: { if (root.layoutsFinalized) return; root.stowFileCand = []; root.stowFileSettled = true; root.maybeFinalizeLayouts(false); }
    }
    // 兜底定案（与 Bar.qml 同构）：两份文件都回执后由 onLoaded 路定案；
    // 某份迟迟不回执（>3s）才强制用现有候选定案，不让整区空白
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
        root.pillMap = { "rec": recPill, "shot": shotPill, "pick": pickPill, "clip": clipPill, "gamma": gammaPill, "theme": themePill, "wall": wallPill, "screen": screenPill };
        console.warn("[toolzone] layout " + JSON.stringify(root.zoneLayout));
        // 整组拖拽信号一次接线：pill 是长命对象，接一次即可（delegate 重建不重复接）
        for (var gpid in root.pillMap)
            root.connectGroupSignals(root.pillMap[gpid]);
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
        var known = ["rec", "shot", "pick", "clip", "gamma", "theme", "wall", "screen"];
        try {
            var data = JSON.parse(txt);
            if (root.validSlots(data, known))
                root.barFileCand = data;
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
    // 联合定案：bar 候选 ∪ stow 候选恰覆盖 8 id 才采用，否则回退默认 + 收纳空
    function maybeFinalizeLayouts(force) {
        if (root.layoutsFinalized)
            return;
        if (!force && !(root.barFileSettled && root.stowFileSettled))
            return;
        root.layoutsFinalized = true;
        var known = ["rec", "shot", "pick", "clip", "gamma", "theme", "wall", "screen"];
        var bar = root.barFileCand;
        var stow = root.stowFileCand;
        var ok = false;
        if (validSlots(bar, known) && validSlots(stow, known)) {
            var seen = {};
            var cnt = 0;
            for (var i = 0; i < bar.length; i++)
                for (var j = 0; j < bar[i].length; j++) { seen[bar[i][j]] = true; cnt++; }
            for (var k = 0; k < stow.length; k++)
                for (var m = 0; m < stow[k].length; m++) { seen[stow[k][m]] = true; cnt++; }
            ok = cnt === known.length && Object.keys(seen).length === known.length;
        }
        if (ok) {
            root.zoneLayout = bar;
            root.stowLayout = stow;
        } else {
            root.zoneLayout = root.defaultZoneLayout;
            root.stowLayout = [];
        }
        console.warn("[toolzone] layout " + JSON.stringify(root.zoneLayout));
        console.warn("[toolzone] stow " + JSON.stringify(root.stowLayout));
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
    // 冻结标志（已收纳 && 本屏抽屉关闭）：左区 8 件都是普通 Pill，文案来自
    // BarState 共享轮询（单进程喂全栏），没有 per-pill exec 可停——这里只如实置位
    // Pill.frozen（当前无消费者），真冻结覆盖在右区 ScriptPill 一侧。
    function applyFrozen() {
        var f = !root.stowOpenHere;
        for (var pid in root.pillMap) {
            var p = root.pillMap[pid];
            if (p)
                p.frozen = f && root.stowHas(pid);
        }
    }
    Connections {
        target: root.uiState
        function onStowOpenChanged() { root.applyFrozen(); }
        function onStowScreenChanged() { root.applyFrozen(); }
    }
    onStowLayoutChanged: root.applyFrozen()
    // 布局变更前把工具 pill 送回仓库，避免 Repeater 重建 delegate 时连带销毁。
    // 只营救「本次真的变了」的区：未变的那份布局赋的是深相等数组，QML 不
    // 发变更通知、Repeater 不重建——全量营救会把未变区整区吞进仓库无人
    // 领养（与 Bar.qml 右区同构的根因，2026-10-22 实测右区双向各吞一整区）
    function rescueAllPills(rescueBar, rescueStow) {
        if (rescueBar) {
            for (var i = 0; i < root.slotItems.length; i++) {
                var s = root.slotItems[i];
                if (!s)
                    continue;
                for (var j = 0; j < s.members.length; j++) {
                    s.members[j].bare = false;
                    s.members[j].drawerMode = false;
                    s.members[j].vertical = false;
                    s.members[j].vCompact = false;
                    s.members[j].parent = toolWarehouse;
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
                    s2.members[j2].bare = false;
                    s2.members[j2].drawerMode = false;
                    s2.members[j2].vertical = false;
                    s2.members[j2].vCompact = false;
                    s2.members[j2].parent = toolWarehouse;
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
    // 落位自愈（兜底，与 Bar.qml 同构）：仍滞留仓库的 pill 按当前模型
    // 确定性地送回其槽的 holder；送不回去的留给调用方打 orphan 留证
    function healOrphans() {
        var healed = [];
        for (var oid in root.pillMap) {
            var p = root.pillMap[oid];
            if (!p || p.parent !== toolWarehouse)
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
            p.vCompact = true;
            healed.push(oid);
        }
        if (healed.length > 0)
            console.warn("[toolzone] healed " + healed.join(","));
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
            root.uiState.dragText = pill.pillText;
            root.uiState.dragBg = pill.normalBg;
            root.uiState.dragFg = pill.normalFg;
            root.uiState.dragW = Math.max(pill.width, 40);
            root.uiState.dragH = pill.height;
            root.uiState.dragX = ap.x + pill.width / 2;
            root.uiState.dragY = ap.y + 16;
        }
        root.uiState.dragScreen = root.screenName;
        root.uiState.dragActive = true;
        // 起拖即展开收纳层（临时模式），并取消上次落位预约的自动收起；
        // 若本屏已是背景手势的持久打开，模式保持不变、拖拽不降级它
        if (!(root.uiState.stowOpen && root.uiState.stowPersistent && root.uiState.stowScreen === root.screenName))
            root.uiState.stowPersistent = false;
        root.uiState.stowScreen = root.screenName;
        root.uiState.stowOpen = true;
        root.uiState.cancelStowClose();
        root.dragTargetType = "none";
        root.dragTargetIndex = -1;
        root.dragTargetZone = "bar";
        root.dragStowHighlightIndex = -1;
        root.dragStowHighlightMode = "";
        root.seamHystBar = -1;
        root.seamHystStow = -1;
    }
    // 插入缝唯一化 + 迟滞（2026-10-22 修插入线在缝两侧跳变，与 Bar.qml 同构）：
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

    // ---------- 竖条拖拽命中（与 Bar 右区同构，无托盘特例）----------
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
        root.uiState.dragX = wx;
        root.uiState.dragY = wy;
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
                    if (fy < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fy > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(toolZoneV);
                if (wy >= zp.y - 10 && wy <= zp.y + toolZoneV.height + 10 && wx >= zp.x - 8 && wx <= zp.x + toolZoneV.width + 8) {
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
        root.uiState.dragX = wx;
        root.uiState.dragY = wy;
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
                    if (fy < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fy > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; gBefore = fy < 0.5; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(toolZoneV);
                if (wy >= zp.y - 10 && wy <= zp.y + toolZoneV.height + 10 && wx >= zp.x - 8 && wx <= zp.x + toolZoneV.width + 8) {
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
        if (type === "none") {
            if (root.stowOpenHere && wx >= b.stowX0 && wx <= b.stowX1 && wy >= 0 && wy <= b.winH) {
                type = "insert"; tIndex = root.stowLayout.length; zone = "stow";
            } else if (wx >= b.barX0 && wx <= b.barX1 && wy >= 0 && wy <= b.winH) {
                var bzp = root.absPosOf(toolZoneV);
                if (wy >= bzp.y - 24 && wy <= bzp.y + toolZoneV.height + 24) {
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
    function pillDragMoved(wx, wy) {
        if (root.vertical) { root.pillDragMovedV(wx, wy); return; }
        if (root.dragId === "")
            return;
        root.uiState.dragX = wx;
        root.uiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var zone = "bar", sHlIndex = -1, sHlMode = "";
        var inBar = wx >= -20 && wy >= root.bandBarY0 && wy <= root.bandBarY1;
        // 收纳层命中（优先于 bar）：抽屉展开且指针在抽屉带（窗口 y 48..92）内，
        // 按抽屉槽判定；规则与 bar 槽同构（边缘 insert / 中心 merge）
        var stowDone = false;
        if (root.stowOpenHere && wx >= -20 && wy >= root.bandStowY0 && wy <= root.bandStowY1) {
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
                    if (fx < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fx > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(toolZone);
                if (wx >= zp.x - 10 && wx <= zp.x + toolZone.width + 10 && wy >= zp.y - 8 && wy <= zp.y + toolZone.height + 8) {
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
        if (root.uiState.stowPersistent)
            root.uiState.cancelStowClose();
        else
            root.uiState.scheduleStowClose();
    }
    function pillDragEnd() {
        root.uiState.dragActive = false;
        var pid = root.dragId;
        if (pid === "")
            return;
        if (root.dragEnding) {
            console.warn("[toolzone] dragEnd reentry blocked " + pid);
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
            console.warn("[toolzone] dragEnd abort: " + pid + " slot " + from + " missing in " + fromZone);
            root.finishDragEnd();
            return;
        }
        var fix = fromArr.indexOf(pid);
        if (fix < 0) {
            console.warn("[toolzone] dragEnd abort: " + pid + " not in slot " + from);
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
            console.warn("[toolzone] dragEnd noop " + pid);
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
        // 落位自检 + 自愈：先 healOrphans 按当前模型确定性归位，再检仍
        // 滞留仓库的才打 orphan 留证
        Qt.callLater(function() {
            root.healOrphans();
            for (var oid in root.pillMap) {
                var op = root.pillMap[oid];
                if (op && op.parent === toolWarehouse)
                    console.warn("[toolzone] orphan " + oid);
            }
        });
        if (barChanged) {
            console.warn("[toolzone] layout " + JSON.stringify(newBar));
            root.exec.sh("printf '%s' '" + JSON.stringify(newBar).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-left.json");
        }
        if (stowChanged) {
            console.warn("[toolzone] stow " + JSON.stringify(newStow));
            root.exec.sh("printf '%s' '" + JSON.stringify(newStow).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-stowed-left.json");
        }
        root.finishDragEnd();
    }

    // ---------- 整组拖拽（长按抓组，与 Bar.qml 同构）----------
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
        root.uiState.dragText = texts.join(" ");
        root.uiState.dragBg = anchor ? anchor.normalBg : root.theme.accent;
        root.uiState.dragFg = anchor ? anchor.normalFg : root.theme.fg;
        root.uiState.dragW = (slotItem && slotItem.width > 0) ? slotItem.width : Math.max(sumW + 2 * (ids.length - 1) + 4, 40);
        root.uiState.dragH = (slotItem && slotItem.height > 0) ? slotItem.height : 32;
        if (slotItem) {
            var sap = root.absPosOf(slotItem);
            root.uiState.dragX = sap.x + slotItem.width / 2;
            root.uiState.dragY = sap.y + 16;
        } else {
            var pap = root.absPosOf(pill);
            root.uiState.dragX = pap.x + pill.width / 2;
            root.uiState.dragY = pap.y + 16;
        }
        root.uiState.dragScreen = root.screenName;
        root.uiState.dragActive = true;
        // 抽屉双模式咬合与 pillDragStart 一致：起拖算一次拖拽开始（临时模式
        // 打开抽屉、落位后预约自动关；持久打开不降级）、取消待发自动关
        if (!(root.uiState.stowOpen && root.uiState.stowPersistent && root.uiState.stowScreen === root.screenName))
            root.uiState.stowPersistent = false;
        root.uiState.stowScreen = root.screenName;
        root.uiState.stowOpen = true;
        root.uiState.cancelStowClose();
        pill.beginGroupDrag();
        console.warn("[toolzone] groupGrab " + JSON.stringify(ids) + " from " + fromZone + " slot " + from);
    }
    // 命中判定与 pillDragMoved 同构（fx 0.22/0.78 边缘、中心 merge、间隙兜底
    // 按槽中心定插入点），差异有二：merge 另记 groupMergeBefore（落点在目标
    // 左半 → 被拖组排在目标成员之前）；两带内未命中任何槽/间隙时按「空白
    // 落位」处理：整组作为独立槽追加到该区末尾（抽屉带全宽适用；顶栏带限
    // 本区槽位带横向范围 ±24）。
    function groupDragMoved(wx, wy) {
        if (root.vertical) { root.groupDragMovedV(wx, wy); return; }
        if (!root.groupActive)
            return;
        root.uiState.dragX = wx;
        root.uiState.dragY = wy;
        var type = "none", tIndex = -1, hlIndex = -1, hlMode = "";
        var zone = "bar", sHlIndex = -1, sHlMode = "";
        var gBefore = false;
        var inBar = wx >= -20 && wy >= root.bandBarY0 && wy <= root.bandBarY1;
        var stowDone = false;
        if (root.stowOpenHere && wx >= -20 && wy >= root.bandStowY0 && wy <= root.bandStowY1) {
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
                    if (fx < 0.22) { type = "insert"; tIndex = i; hlIndex = i; hlMode = "insertL"; }
                    else if (fx > 0.78) { type = "insert"; tIndex = i + 1; hlIndex = i; hlMode = "insertR"; }
                    else { type = "merge"; tIndex = i; hlIndex = i; hlMode = "merge"; gBefore = fx < 0.5; }
                    break;
                }
            }
            if (hit < 0 && root.slotItems.length > 0) {
                var zp = root.absPosOf(toolZone);
                if (wx >= zp.x - 10 && wx <= zp.x + toolZone.width + 10 && wy >= zp.y - 8 && wy <= zp.y + toolZone.height + 8) {
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
            if (root.stowOpenHere && wx >= -20 && wy >= root.bandStowY0 && wy <= root.bandStowY1) {
                type = "insert"; tIndex = root.stowLayout.length; zone = "stow";
            } else if (wx >= -20 && wy >= root.bandBarY0 && wy <= root.bandBarY1) {
                var bzp = root.absPosOf(toolZone);
                if (wx >= bzp.x - 24 && wx <= bzp.x + toolZone.width + 24) {
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
        root.uiState.dragActive = false;
        if (!root.groupActive)
            return;
        if (root.dragEnding) {
            console.warn("[toolzone] groupDragEnd reentry blocked");
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
            console.warn("[toolzone] groupDragEnd abort: source slot mismatch at " + fromZone + " slot " + from);
            root.finishDragEnd();
            return;
        }
        srcLayout.splice(from, 1);
        var shift = (fromZone === toZone && from < t) ? 1 : 0;
        if (type === "merge") {
            var tgt = dstLayout[t - shift];
            if (!tgt) {
                console.warn("[toolzone] groupDragEnd abort: merge target missing");
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
            console.warn("[toolzone] groupDragEnd noop " + JSON.stringify(ids));
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
                if (op && op.parent === toolWarehouse)
                    console.warn("[toolzone] orphan " + oid);
            }
        });
        if (barChanged) {
            console.warn("[toolzone] layout " + JSON.stringify(newBar));
            root.exec.sh("printf '%s' '" + JSON.stringify(newBar).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-left.json");
        }
        if (stowChanged) {
            console.warn("[toolzone] stow " + JSON.stringify(newStow));
            root.exec.sh("printf '%s' '" + JSON.stringify(newStow).replace(/'/g, "") + "' > ~/.cache/by-mgr/qs-bar-layout-stowed-left.json");
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
            // 竖条时 holder 高跟 pill 的竖向收展（animH），横向恒 32
            height: root.vertical ? (pillRef ? pillRef.animH : 0) : 32
            clip: true
            opacity: ((root.dragId !== "" && root.dragId === pillId) || (root.groupActive && root.groupIds.indexOf(pillId) >= 0)) ? 0.35 : 1
            Behavior on opacity { NumberAnimation { duration: 120 } }
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
            // 竖条时槽位尺寸轴互换：高 = 成员 animH 之和（组 +2 上下边；
            // 工具条块间间距已收到最小，槽内列间距为 0，公式里不再加间隙项），
            // 宽 = 成员 animW 最大值（组与单槽同宽，无左右边）；横向与改前一致
            height: root.vertical ? (function() {
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animH;
                if (members.length >= 2)
                    return anyShown ? s + 2 : 0;
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
                spacing: 0
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
                    pill.drawerMode = false;
                    pill.vertical = root.vertical;
                    pill.vCompact = true;
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
                    members[i].vCompact = false;
                    members[i].parent = toolWarehouse;
                }
                root.unregisterSlot(index, slot);
            }
        }
    }

    // 收纳槽位：与 slotDelegate 同构，差异仅在注册表走 stowSlotItems、
    // 高亮读 dragStowHighlight* 且须 dragTargetZone=stow
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
            // 竖条时槽位尺寸轴互换：高 = 成员 animH 之和（组 +2 上下边；
            // 工具条块间间距已收到最小，槽内列间距为 0，公式里不再加间隙项），
            // 宽 = 成员 animW 最大值（组与单槽同宽，无左右边）；横向与改前一致
            height: root.vertical ? (function() {
                var s = 0;
                for (var i = 0; i < members.length; i++)
                    s += members[i].animH;
                if (members.length >= 2)
                    return anyShown ? s + 2 : 0;
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
                spacing: 0
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
                    pill.vCompact = true;
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
                    members[i].vCompact = false;
                    members[i].parent = toolWarehouse;
                }
                root.unregisterStowSlot(index, slot);
            }
        }
    }

    // 工具仓库：8 件声明停在这里（隐藏不排版），由 toolZone 槽位按 zoneLayout 领养。
    // 点击行为从原托盘逐条迁来（左键/右键/补刷），一条不丢。
    Item {
        id: toolWarehouse
        visible: false
        width: 0
        height: 0

        // 录制
        Pill {
            id: recPill
            pillId: "rec"
            dragEnabled: true
            normalBg: theme.accent
            normalFg: (barState.recC === "recording" || barState.recC === "kernel" || barState.recC === "many" || barState.recC === "inhibited") ? theme.clockFg : theme.fg
            pillText: barState.recT
            textSize: 14
            onLeftClicked: {
                root.exec.sh("~/.config/rofi/scripts/recorder.sh");
                root.barState.refresh();
            }
            onRightClicked: {
                root.exec.sh("pkill -INT -f gpu-screen-recorder");
                root.barState.refresh();
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 截图
        Pill {
            id: shotPill
            pillId: "shot"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.shotT
            textSize: 14
            onLeftClicked: root.exec.sh("bash " + root.exec.commonDir + "/screenshot.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 取色
        Pill {
            id: pickPill
            pillId: "pick"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.pickT
            textSize: 14
            onLeftClicked: root.exec.sh("bash " + root.exec.commonDir + "/pick-color.sh")
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 剪贴板
        Pill {
            id: clipPill
            pillId: "clip"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.clipT
            textSize: 14
            onLeftClicked: root.exec.sh("copyq toggle")
            onRightClicked: root.exec.sh("copyq eval \\\"clear()\\\" 2>/dev/null; notify-send \\\"剪贴板\\\" \\\"已清空\\\"");
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 护眼
        Pill {
            id: gammaPill
            pillId: "gamma"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.gammaT
            textSize: 14
            onLeftClicked: {
                root.exec.sh("bash " + root.exec.commonDir + "/gamma-toggle.sh");
                root.barState.refreshOne("gamma", "bash " + root.exec.commonDir + "/gammastep.sh");
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 主题
        Pill {
            id: themePill
            pillId: "theme"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.themeT
            textSize: 14
            onLeftClicked: {
                root.exec.sh("bash ~/.config/niri/scripts/toggle-theme.sh");
                root.barState.refresh();
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 壁纸
        Pill {
            id: wallPill
            pillId: "wall"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: icons.wallpaper
            textSize: 14
            onLeftClicked: root.uiState.toggleWallpaperPicker(root.screenName)
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
        // 显示器
        Pill {
            id: screenPill
            pillId: "screen"
            dragEnabled: true
            normalBg: theme.accent; normalFg: theme.fg
            pillText: barState.screenT
            textSize: 14
            onLeftClicked: {
                root.exec.sh("bash " + root.exec.commonDir + "/screen.sh menu");
                root.barState.refresh();
            }
            onDragStarted: pid => root.pillDragStart(pid)
            onDragMoved: (wx, wy) => root.pillDragMoved(wx, wy)
            onDragEnded: root.pillDragEnd()
        }
    }

    // 工具胶囊区：按 zoneLayout 渲染槽位（单颗/组合）
    Row {
        id: toolZone
        spacing: 2
        height: 32
        visible: !root.vertical
        Repeater {
            model: root.zoneReady && !root.vertical ? root.zoneLayout : []
            delegate: slotDelegate
        }
    }
    // 竖条工具区：与横向同模型、双 Repeater 切模型（只一个有 delegate）
    Column {
        id: toolZoneV
        spacing: 1
        visible: root.vertical
        Repeater {
            model: root.zoneReady && root.vertical ? root.zoneLayout : []
            delegate: slotDelegate
        }
    }
}
