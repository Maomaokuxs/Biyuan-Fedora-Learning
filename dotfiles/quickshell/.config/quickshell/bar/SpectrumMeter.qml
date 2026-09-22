import QtQuick
import "../components" as Comp

// 声谱柱：数据直给高度，无趋近无 tween 无死区——
// 实测直给稳，抖全是显示层后加的；平滑由 spectrum.py 的 VU 弹道负责。
// 镜像取大（非平均）：对称外观不变，动态不砍半，无需补偿增益。
// dance 模式下本文件不实例化，进程由 SpectrumState 按需启停。
Item {
    id: root
    property var theme

    property int bars: 12
    property var levels: []
    // 最新帧暂存，取帧时钟按固定节拍消费（数据 23Hz 推多少吃多少会错拍 judder）
    property var pending: []
    property bool playing: Comp.SpectrumState.anyPlaying
    onPlayingChanged: {
        // 暂停即压平（旧版暂停冻柱是 bug）
        if (!root.playing)
            root.levels = [];
    }

    property var liveBands: Comp.SpectrumState.bands
    onLiveBandsChanged: {
        var live = root.liveBands;
        if (live.length < 12)
            return;
        root.pending = live.slice(0, 12);
    }

    // 取帧时钟：80ms 定节拍（源头 12Hz，同拍不打架），只取最新一帧；
    // 与上次完全一致就跳过落盘（VU 到站后源头吐重复帧，不写即不重绘）
    Timer {
        interval: 80
        running: root.playing
        repeat: true
        onTriggered: {
            var live = root.pending;
            if (live.length < 12)
                return;
            var half = [];
            for (var j = 0; j < 6; j++)
                half.push(Math.max(live[j], live[11 - j]));
            var target = half.concat(half.slice().reverse()).slice(0, root.bars);
            var cur = root.levels;
            var same = cur.length === root.bars;
            if (same)
                for (var i = 0; i < root.bars; i++)
                    if (cur[i] !== target[i]) {
                        same = false;
                        break;
                    }
            if (!same)
                root.levels = target;
        }
    }

    Row {
        anchors.centerIn: parent
        spacing: 2
        Repeater {
            model: root.bars
            Rectangle {
                required property int index
                property real v: (root.levels.length > index) ? root.levels[index] : 0
                // 低端落点：v<0.15 一律按 0 趴下——小值在 1px 台阶上来回 cross 就是碎闪，
                // 趴下和 3px 基线圆点视觉无差，真起量（>0.15）照样起来
                property real vc: v < 0.15 ? 0 : v
                width: 5
                // 全浮点走完全程，落像素时归一钳位（量化只发生这一次）
                height: Math.max(3, Math.min(1, vc) * 24)
                anchors.verticalCenter: parent.verticalCenter
                radius: 2.5
                color: root.theme ? root.theme.fg : "#6a442f"
            }
        }
    }
}
