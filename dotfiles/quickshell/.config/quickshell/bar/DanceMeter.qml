import QtQuick
import "../components" as Comp

// 律动舞者：不读实时分频，只做得好看。
// 纯时间函数动画：正弦干涉编排由 tick 时钟推进，开关只看播放状态；
// 峰值事件仅提供幅度包络，断流时用假设包络续跳（源哑了也不冻）。
// 峰值源走 SpectrumState（spectrum.py pw-record 直采），
// PwNodePeakMonitor 在 pipewire 1.6 下永不 ready，已弃用。
// 对称镜像；暂停即回基线停摆。无音频占用时主动关闭轮询（零 Process 泡水）。
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
    // wantSource 落进 SpectrumState 启停门：把 ^ property 传过去让它控制进程启停
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

    property bool wantSource: root.anyPlaying && !Comp.BarState.flagM && (root.dancing || Comp.UiState.vizEffect === "spectrum")
    Component.onCompleted: {
        if (root.anyPlaying)
            root.poke();
        Comp.BarState.danceAlive = Qt.binding(function() { return root.wantSource; });
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

    // 峰值后端：走 Comp.SpectrumState 频谱带（spectrum.py pw-record 直采），
    // 合成包络 v = max(bands)。PwNodePeakMonitor 在 pipewire 1.6 下永不 ready，弃用。
    // 按需监听：无 Mpris/已停摆/总闸拉下时零 Process 流量；
    // 启动靠 anyPlaying（Mpris），恢复靠留守 band 峰值，来声即 poke
    Timer {
        id: monitor
        // 峰值直读 SpectrumState.bands（spectrum.py 输出，80ms 节奏）
        interval: 80
        running: root.dancing || (root.anyPlaying && !Comp.BarState.flagM)
        repeat: true
        onTriggered: {
            var bands = Comp.SpectrumState.bands;
            var v = 0;
            for (var i = 0; i < bands.length; i++)
                v = Math.max(v, bands[i]);
            // 与历史 peak 语义对齐：频谱带是"分频后每柱满格"的量纲，
            // peak monitor 是整段 RMS；取 max 后除 2 再二次曲线压顶部，
            // 让包络量级回到历史 peak 的尺度（0-0.6 为主），
            // 上不封顶保住大动态，下自然趋零
            v = Math.max(0, Math.min(1, v / 1.5));
            v = v * v * 0.9;
            // 静默时钟只认真峰值
            if (v > 0.02)
                root.lastPeakT = Date.now();
            // 包络跟随：与历史版完全同参（0.12/0.015 重低通），只取大势不吃碎拍
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
            // 空转优雅退出： bands 长期为空且没在跳，关掉自己的轮询
            if (bands.length === 0 && nowB - root.lastPeakT > root.idleMs) {
                monitor.running = false;
            }
        }
    }
}
