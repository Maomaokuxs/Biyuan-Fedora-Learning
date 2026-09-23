import QtQuick
import Quickshell.Services.Pipewire
import "../components" as Comp

// 律动舞者：不读实时分频，只做得好看。
// 纯时间函数动画：正弦干涉编排由 tick 时钟推进，开关只看播放状态；
// 峰值事件仅提供幅度包络，断流时用假设包络续跳（monitor 哑了也不冻）。
// 对称镜像；暂停即回基线停摆。spectrum 模式下本文件不实例化，monitor 零开销。
// 无音频占用时主动关闭：无 Mpris 播放 → 停摆 + 关 monitor（零 PipeWire 流量）；
// 有 Mpris 但 15s 无峰值（哑流/断连）→ 同样停摆，monitor 留守，来声即恢复。
Item {
    id: root
    property var theme

    property int bars: 12
    property var levels: []
    // 响度包络（稀疏采样）与舞步时钟
    property real energy: 0
    property real tick: 0
    property double lastSoundT: 0
    property bool dancing: false
    // 播放开关走 SpectrumState 单一事实源（不另建 Mpris 绑定）
    property bool anyPlaying: Comp.SpectrumState.anyPlaying
    // 哑流超时：有 Mpris 但这么久无峰值，视为无音频占用，主动停摆
    property int idleMs: 15000
    property double lastPeakT: 0
    function poke() {
        var now = Date.now();
        root.lastSoundT = now;
        root.lastPeakT = now;
        if (!root.dancing)
            root.dancing = true;
    }
    function shutdown() {
        root.dancing = false;
        root.levels = [];
        root.energy = 0;
        root.business = 0;
        root.beatPulse = 0;
        root.beatAvg = 0;
    }
    onAnyPlayingChanged: {
        if (root.anyPlaying)
            root.poke();
        else
            root.shutdown();
    }
    Component.onCompleted: {
        if (root.anyPlaying)
            root.poke();
    }
    // 忙闲度：连续峰值差分大=忙（快歌/鼓点密），小=舒缓
    property real business: 0
    property real lastPeak: 0
    // 拍点：均值跟踪 + 突发放量检测（250ms 消抖），检到置 1 由舞步衰减
    property real beatAvg: 0
    property real beatPulse: 0
    property double lastBeatT: 0
    // 波形号与平静武装位（换场逻辑见舞步时钟）
    // 编排混合器：patA→patB smoothstep 交叉淡化约 2.5s，切换永不跳变；
    // -1 自动（一次一式，跟音乐换场），0-7 固定单式，8 混合（八式同放）
    // （VizCard 可选；混合≠自动轮播：一个同时叠加，一个一次一式）
    property int patA: 0
    property int patB: 0
    property real mix: 1
    property int dancePat: Comp.UiState.dancePattern
    onDancePatChanged: {
        if (root.dancePat >= 0 && root.dancePat <= 7)
            root.startBlend(root.dancePat);
        else if (root.dancePat === -1)
            root.wasCalm = true;
    }
    function startBlend(n) {
        n = ((n % 8) + 8) % 8;
        if (n === root.patB)
            return;
        // 落定才挪基座；在途改道不断基座，只换目标、无缝续淡
        if (root.mix >= 1)
            root.patA = root.patB;
        root.patB = n;
        root.mix = 0;
    }
    property bool wasCalm: true

    // GPU 柱：12 个圆角矩形场景节点，高度绑 levels，无 CPU 光栅化。
    // 中间对称，静默剩基线圆点。
    Row {
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: root.bars
            Rectangle {
                required property int index
                property real v: (root.levels.length > index) ? root.levels[index] : 0
                width: 5
                height: Math.max(3, Math.min(1, v) * 24)
                anchors.verticalCenter: parent.verticalCenter
                radius: 2.5
                color: root.theme ? root.theme.fg : "#6a442f"
            }
        }
    }

    // 舞步时钟：50ms，慢正弦编排；高度直给（正弦连续，无 tween 无趋近）
    Timer {
        id: danceTimer
        interval: 50
        running: root.dancing
        repeat: true
        onTriggered: {
            // 暂停即停摆；peak 断流但仍在播→用假设包络续跳（纯函数动画不死机）
            var now = Date.now();
            var stale = now - root.lastPeakT > 1500;
            // 暂停或总闸拉下 → 主动停摆（尾闸不管本模块活动，只藏跟随者）
            if (!root.anyPlaying || Comp.BarState.flagM) {
                root.shutdown();
                return;
            }
            // 哑流超时：Mpris 在播但长期无峰值 → 无音频占用，主动停摆；
            // monitor 留守（anyPlaying 仍真），来声即恢复
            if (now - root.lastPeakT > root.idleMs) {
                root.shutdown();
                return;
            }
            root.tick += 1;
            var t = root.tick;
            var e = stale ? Math.max(root.energy, 0.45) : root.energy;
            // 拍点衰减（慢放，轻泵不砸盘）
            root.beatPulse = root.beatPulse * 0.9;
            var thump = root.beatPulse * 0.35 * Math.max(e, 0.15);
            // 忙则幅大、闲则幅小：0.35 保底轻晃
            var biz = stale ? Math.max(root.business, 0.5) : root.business;
            var amp = (0.35 + 0.65 * biz) / 0.7;
            function waveFor(m, tt, mi) {
                if (m === 0)
                    return 0.5 + 0.5 * Math.sin(tt * 0.35 + mi * 0.9);  // 起伏
                if (m === 1)
                    return 0.5 + 0.5 * Math.sin(tt * 0.5 - mi * 1.3);  // 斜纹
                if (m === 2)
                    return (0.5 + 0.5 * Math.sin(tt * 0.2 + mi * 0.5)) * (0.5 + 0.5 * Math.sin(tt * 0.07));  // 呼吸
                if (m === 3)
                    return 0.5 + 0.5 * Math.sin(tt * 0.6 + (mi % 2) * Math.PI);  // 交错
                if (m === 4) {  // 脉冲：对称双峰来回扫
                    var dd = (mi - (2.5 + 2.5 * Math.sin(tt * 0.12))) / 1.1;
                    return Math.exp(-dd * dd);
                }
                if (m === 5)  // 驼峰：密波纹
                    return 0.5 + 0.5 * Math.sin(tt * 0.25 + mi * 1.8);
                if (m === 6) {  // 闪烁：每 10 拍一跳，输出跟随抹成滑行
                    var hh = Math.sin((mi * 7 + Math.floor(tt / 10)) * 127.1) * 43758.5;
                    return hh - Math.floor(hh);
                }
                return Math.pow(0.5 + 0.5 * Math.sin(tt * 0.3 + mi * 0.9), 2);  // 峭壁：尖峰宽谷
            }
            // 平静→激昂跳变点换场（仅自动模式）：先跌到 0.2 以下武装，冲上 0.55 开火；
            // 无定时，纯跟音乐走；换场走混合器，不断层
            if (root.dancePat === -1 && biz < 0.2) {
                root.wasCalm = true;
            } else if (root.dancePat === -1 && root.wasCalm && biz > 0.55) {
                root.startBlend(root.patB + 1);
                root.wasCalm = false;
            }
            // 混合推进：2.5s 一次淡化，落定即合上基座
            if (root.mix < 1) {
                root.mix = Math.min(1, root.mix + 0.02);
                if (root.mix >= 1)
                    root.patA = root.patB;
            }
            var next = [];
            var cur0 = root.levels;
            var maxd = 0;
            // 双编排混合输出：smoothstep 淡化，默认即混合态，切歌单无棱角；
            // 混合模式四式同放取均值（与自动轮播是两回事）
            var s = root.mix >= 1 ? 1 : root.mix * root.mix * (3 - 2 * root.mix);
            var isMixAll = root.dancePat === 8;
            for (var i = 0; i < root.bars; i++) {
                var mi = Math.min(i, root.bars - 1 - i);
                var w;
                if (isMixAll) {
                    // 混合：八式同放取均值，干涉出复合波形（与自动轮播是两回事）
                    w = 0;
                    for (var mm = 0; mm < 8; mm++)
                        w += waveFor(mm, t, mi);
                    w /= 8;
                } else {
                    w = waveFor(root.patA, t, mi) * (1 - s) + waveFor(root.patB, t, mi) * s;
                }
                var target = Math.min(1, e * (0.2 + 0.8 * w) * amp + thump);
                var old0 = cur0.length > i ? cur0[i] : 0;
                // 输出跟随抹平切歌单间的棱角
                var k = target > old0 ? 0.6 : 0.25;
                var nv = old0 + (target - old0) * k;
                next.push(nv);
                var dd = Math.abs(nv - old0);
                if (dd > maxd)
                    maxd = dd;
            }
            // 变化门限：和上一帧差不到 0.015 就不落盘、不重绘，静态段零 paint
            if (maxd >= 0.015 || cur0.length !== root.bars)
                root.levels = next;
        }
    }

    PwNodePeakMonitor {
        id: monitor
        node: Pipewire.ready ? Pipewire.defaultAudioSink : null
        // 按需监听：无 Mpris/已停摆/总闸拉下时关闭，零 PipeWire 流量；
        // 启动靠 anyPlaying（Mpris），恢复靠留守监听中的峰值，来声即 poke
        enabled: node !== null && (root.anyPlaying || root.dancing) && !Comp.BarState.flagM
        onPeaksChanged: {
            var v = 0;
            for (var i = 0; i < peaks.length; i++)
                v = Math.max(v, peaks[i]);
            v = Math.max(0, Math.min(1, v));
            // 静默时钟只认真峰值：空闲 sink 也可能吐全零事件，用它刷新时钟
            // 会导致哑流熄火永不触发、假设包络空跳到天荒地老
            if (v > 0.02)
                root.lastPeakT = Date.now();
            // 包络跟随：重低通，只取大势不吃碎拍（跟太紧就是抖）
            root.energy = root.energy + (v - root.energy) * (v > root.energy ? 0.12 : 0.015);
            var diff = Math.abs(v - root.lastPeak);
            root.lastPeak = v;
            var inst = Math.min(1, diff * 6);
            root.business = root.business + (inst - root.business) * (inst > root.business ? 0.08 : 0.008);
            // 拍点检测：突发放量超均值 40% 且过门限，250ms 内只算一次
            root.beatAvg = root.beatAvg + (v - root.beatAvg) * 0.05;
            var nowB = Date.now();
            if (v > root.beatAvg * 1.4 + 0.08 && v > 0.12 && nowB - root.lastBeatT > 250) {
                root.beatPulse = 1;
                root.lastBeatT = nowB;
            }
            if (v > 0.03) {
                root.lastSoundT = Date.now();
                if (!root.dancing)
                    root.dancing = true;
            }
        }
    }
}
