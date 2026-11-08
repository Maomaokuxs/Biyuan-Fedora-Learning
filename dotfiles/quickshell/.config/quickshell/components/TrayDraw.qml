import QtQuick

// 托盘统一绘制：按原图标形状画，统一只统一颜色/线粗/尺寸。
// 视觉归一：每格墨迹框都收进约 17-20 格、线粗收进 3-4 格，
// 细轮廓（剪刀/方印/电视）加粗、粗填充（斜杠/圆盘）收小，
// 否则同 14px 下有的显大有的显小。
// 画法取自实测原托盘图标：蓝牙符、FlClash 斜杠、AB 箭头+碗、CopyQ 剪刀、
// fcitx-rime 方印+中、SPlayer 圆盘+音符、B站电视+字、Kazumi 长发头、QQ 企鹅、微信双气泡。
// 颜色跟主题走（drawColor=主题字色，bgColor=托盘条带底色，镂空用底色画，
// 换壁纸自动跟变）；未映射时 drawKey 为空，delegate 回落原图。
Canvas {
    id: root
    property string trayId: ""
    property string trayTitle: ""
    property string trayIcon: ""
    property color drawColor: "#000000"
    property color bgColor: "#ffffff"
    // 输入法中/英：由 Bar 传 fcitxPill.pillText（fcitx_status.sh 每秒轮询
    // fcitx5-remote -n，keyboard-us 为 EN、其余为中）；托盘 SNI 的 icon 名
    // 在 wetypex 与 keyboard-us 下都是 input-keyboard，分不出中英文，
    // 所以 TrayDraw 不能只看 icon，必须跟 pill 同一个来源
    property string fcitxLang: "中"
    property bool isDisabled: String(trayIcon || "").indexOf("disabled") !== -1
    property string drawKey: {
        var s = String(trayId || "") + "|" + String(trayTitle || "") + "|" + String(trayIcon || "");
        if (s.indexOf("blueman") !== -1) return "blueman";
        if (s.indexOf("com.follow.clash") !== -1 || s.indexOf("FlClash") !== -1) return "flclash";
        if (s.indexOf("AB Download") !== -1) return "abdownload";
        if (s.indexOf("CopyQ") !== -1) return "copyq";
        if (s.indexOf("Fcitx") !== -1) return "fcitx";
        if (s.indexOf("SPlayer") !== -1) return "splayer";
        if (s.indexOf("bilibili") !== -1) return "bilibili";
        if (s.indexOf("kazumi") !== -1 || s.indexOf("Predidit.Kazumi") !== -1) return "kazumi";
        if (s.indexOf("com.qq.QQ") !== -1 || s.indexOf("QQ") !== -1 || s.indexOf("chrome_status_icon_1") !== -1) return "qq";
        if (s.indexOf("wechat") !== -1) return "wechat";
        return "";
    }

    width: 20
    height: 20
    visible: drawKey !== ""

    onDrawColorChanged: requestPaint()
    onBgColorChanged: requestPaint()
    onFcitxLangChanged: requestPaint()
    onDrawKeyChanged: requestPaint()
    onIsDisabledChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, 20, 20);
        if (drawKey === "")
            return;
        // 24 格坐标系画，缩放到 20px（托盘格 24px，留 2px 边；未映射的原图也是 20px）
        ctx.scale(20 / 24, 20 / 24);
        ctx.strokeStyle = drawColor;
        ctx.fillStyle = drawColor;
        ctx.lineCap = "round";
        ctx.lineJoin = "round";

        function line(x1, y1, x2, y2, w) {
            ctx.lineWidth = w;
            ctx.beginPath();
            ctx.moveTo(x1, y1);
            ctx.lineTo(x2, y2);
            ctx.stroke();
        }
        function polyline(pts, w) {
            ctx.lineWidth = w;
            ctx.beginPath();
            ctx.moveTo(pts[0][0], pts[0][1]);
            for (var i = 1; i < pts.length; i++)
                ctx.lineTo(pts[i][0], pts[i][1]);
            ctx.stroke();
        }
        function dot(x, y, r, color) {
            ctx.fillStyle = color;
            ctx.beginPath();
            ctx.arc(x, y, r, 0, Math.PI * 2);
            ctx.fill();
            ctx.fillStyle = drawColor;
        }
        function ring(x, y, r, w, color) {
            ctx.strokeStyle = color;
            ctx.lineWidth = w;
            ctx.beginPath();
            ctx.arc(x, y, r, 0, Math.PI * 2);
            ctx.stroke();
            ctx.strokeStyle = drawColor;
        }
        // 椭圆描边/椭圆弧：用折线逼近椭圆（Canvas 线宽会被 scale 放大，
        // 直接 scale 画椭圆会把 3 格线撑成实心块，所以不用 scale 画法）
        function ell(cx, cy, rx, ry, a0, a1, w) {
            ctx.lineWidth = w;
            ctx.beginPath();
            var n = 40;
            for (var i = 0; i <= n; i++) {
                var a = a0 + (a1 - a0) * i / n;
                var x = cx + rx * Math.cos(a);
                var y = cy + ry * Math.sin(a);
                if (i === 0) ctx.moveTo(x, y);
                else ctx.lineTo(x, y);
            }
            ctx.stroke();
        }

        if (drawKey === "blueman") {
            // 原符天生窄（宽 10 格），横向拉宽到 14 格才跟其他格视觉等大；
            // 关的状态按原图画右下角叉号徽标（底色圆底 + 主色叉），符本身保持完整
            polyline([[5, 7], [19, 17], [12, 22], [12, 2], [19, 7], [5, 17]], 3);
            if (isDisabled) {
                ctx.fillStyle = bgColor;
                ctx.beginPath();
                ctx.arc(18.5, 18.5, 3.5, 0, Math.PI * 2);
                ctx.fill();
                ctx.strokeStyle = drawColor;
                line(16.5, 16.5, 20.5, 20.5, 2);
                line(20.5, 16.5, 16.5, 20.5, 2);
            }
        } else if (drawKey === "flclash") {
            // 斜杠原 5 格太粗，收 4 格
            line(3, 10, 21, 3, 4);
            line(7, 17, 18, 13, 4);
            dot(13, 21, 2.5, drawColor);
        } else if (drawKey === "abdownload") {
            // 碗收进画布：圆心 (12,15) 半径 8，底到 23，不再超出 24 格被截
            line(12, 3, 12, 13, 4);
            polyline([[8, 9], [12, 13], [16, 9]], 4);
            ctx.lineWidth = 4;
            ctx.beginPath();
            ctx.arc(12, 15, 8, 0, Math.PI);
            ctx.stroke();
        } else if (drawKey === "copyq") {
            // 剪刀原 2-2.5 格太细，加到 3 格
            ring(8, 7, 4, 3, drawColor);
            ring(16, 7, 4, 3, drawColor);
            dot(8, 7, 1.8, bgColor);
            dot(16, 7, 1.8, bgColor);
            line(11, 11, 17, 21, 3);
            line(13, 11, 7, 21, 3);
        } else if (drawKey === "fcitx") {
            // 方印外框改回 2 格（3 格太粗）；中/英跟 fcitxLang 走
            // 方框加大到 20 格（原 18 格比上面一行矮），字跟着放大
            ctx.lineWidth = 2;
            ctx.strokeRect(2, 2, 20, 20);
            ctx.fillStyle = drawColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            if (fcitxLang === "EN") {
                ctx.font = "bold 11px 'JetBrainsMono Nerd Font', sans-serif";
                ctx.fillText("EN", 12, 12.5);
            } else {
                ctx.font = "15px 'Sarasa Gothic SC', sans-serif";
                ctx.fillText("中", 12, 12.5);
            }
        } else if (drawKey === "splayer") {
            // 实心盘加大到直径 20 格（原 18 格仍比上面一行矮），音符镂空同比例放大
            ctx.beginPath();
            ctx.arc(12, 12, 10, 0, Math.PI * 2);
            ctx.fill();
            // 音符用底色镂空（原图白音符），随盘同比例收
            ctx.fillStyle = bgColor;
            ctx.fillRect(13.9, 5.1, 2.6, 11.2);
            ctx.fillRect(14.6, 5.1, 6.9, 4.3);
            ctx.strokeStyle = bgColor;
            ctx.lineWidth = 2.5;
            ctx.save();
            ctx.translate(10.8, 17);
            ctx.scale(3.8 / 3.1, 1);
            ctx.beginPath();
            ctx.arc(0, 0, 3.1, 0, Math.PI * 2);
            ctx.stroke();
            ctx.restore();
        } else if (drawKey === "bilibili") {
            // 电视原高只有 11 格最显小：框加高到 13 格、线加到 3 格、字加大
            line(7, 6, 4, 2, 3);
            line(17, 6, 20, 2, 3);
            ctx.lineWidth = 3;
            ctx.strokeRect(2.5, 6, 19, 13);
            ctx.fillStyle = drawColor;
            ctx.font = "5px sans-serif";
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            ctx.fillText("bilibili", 12, 12.5);
        } else if (drawKey === "kazumi") {
            // 长发头 14px 版（mock7）：发廓、刘海一个浅 V、两眼两竖杠；下巴/发丝/空心眼全删
            line(3, 22, 3, 9, 3);
            line(21, 22, 21, 9, 3);
            ell(12, 9, 9, 7, Math.PI, Math.PI * 2, 3);
            polyline([[7, 9], [12, 11.5], [17, 9]], 2.5);
            line(9, 10.5, 9, 14.5, 3);
            line(15, 10.5, 15, 14.5, 3);
        } else if (drawKey === "qq") {
            // 企鹅 14px 版（mock7）：梨形身廓上窄下宽、两眼竖杠、扁嘴、围巾一根粗横带
            // QQ 是 Electron，走 Chromium 的 chrome_status_icon_1（Id/Title/Icon 全无 QQ 字样，
            // 2026-11-07 实取 pixmap 确认是企鹅）；原生 Chrome 也用同一 Id，届时再区分
            // 身廓改回一笔画椭圆：梨形是四段拼的，段与段接头处对不齐才出锯齿
            ell(12, 12, 9, 11, 0, Math.PI * 2, 3);
            // 中间简化：眼改两点、嘴改一横线（竖杠眼+椭圆嘴在 14px 下糊成一团）
            dot(9.5, 6.5, 1.5, drawColor);
            dot(14.5, 6.5, 1.5, drawColor);
            line(8, 10.5, 16, 10.5, 3);
            line(4, 14.5, 20, 14.5, 4);
            // 腿：底边两侧两只脚弧，按原图量：左脚 x 4.7-12.0、右脚 x 12.1-19.3，y 21.7-23.6，
            // 两只又宽又扁、中间在 x=12 处会合，比之前的小弧更往外
            ell(8.3, 22.1, 3.6, 1.5, 0, Math.PI, 2);
            ell(15.7, 22.1, 3.6, 1.5, 0, Math.PI, 2);
        } else if (drawKey === "wechat") {
            // 双气泡按原图标（flatpak 应用图标 256px）实测比例：
            // 大泡中心 (9.4,10) rx 6.1 ry 4.9（宽椭圆）、小泡中心 (15.9,12.7) rx 4.7 ry 3.7，
            // 大泡尾在左下 (6,17.3)、小泡尾在右下 (18.3,18.8)，各泡两眼。
            // 原图本就宽扁（高只有 13.7 格），整体均匀放大 1.15 倍顶满宽度，比例不动
            ctx.save();
            ctx.translate(12, 12);
            ctx.scale(1.15, 1.15);
            ctx.translate(-12, -12);
            ell(9.4, 10, 6.1, 4.9, 0, Math.PI * 2, 3);
            polyline([[7, 14], [6, 17.3], [8.5, 14.5]], 3);
            ell(15.9, 12.7, 4.7, 3.7, 0, Math.PI * 2, 3);
            polyline([[18, 15.5], [18.3, 18.8], [16.5, 16]], 3);
            dot(8, 8.9, 1.5, drawColor);
            dot(11.7, 8.9, 1.5, drawColor);
            dot(14.5, 11.7, 1.5, drawColor);
            dot(17.3, 11.7, 1.5, drawColor);
            ctx.restore();
        }
    }
}
