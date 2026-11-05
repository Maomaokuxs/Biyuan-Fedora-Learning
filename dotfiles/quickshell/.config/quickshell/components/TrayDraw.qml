import QtQuick

// 托盘统一绘制：按原图标形状画，统一只统一颜色/线粗/尺寸。
// 视觉归一：每格墨迹框都收进约 17-20 格、线粗收进 3-4 格，
// 细轮廓（剪刀/方印/电视）加粗、粗填充（斜杠/圆盘）收小，
// 否则同 14px 下有的显大有的显小。
// 画法取自实测原托盘图标：蓝牙符、FlClash 斜杠、AB 箭头+碗、CopyQ 剪刀、
// fcitx-rime 方印+中、SPlayer 圆盘+音符、B站电视+字。
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
        return "";
    }

    width: 14
    height: 14
    visible: drawKey !== ""

    onDrawColorChanged: requestPaint()
    onBgColorChanged: requestPaint()
    onFcitxLangChanged: requestPaint()
    onDrawKeyChanged: requestPaint()
    onIsDisabledChanged: requestPaint()

    onPaint: {
        var ctx = getContext("2d");
        ctx.setTransform(1, 0, 0, 1, 0, 0);
        ctx.clearRect(0, 0, 14, 14);
        if (drawKey === "")
            return;
        // 24 格坐标系画，缩放到 14px
        ctx.scale(14 / 24, 14 / 24);
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
            ctx.lineWidth = 2;
            ctx.strokeRect(3, 3, 18, 18);
            ctx.fillStyle = drawColor;
            ctx.textAlign = "center";
            ctx.textBaseline = "middle";
            if (fcitxLang === "EN") {
                ctx.font = "bold 10px 'JetBrainsMono Nerd Font', sans-serif";
                ctx.fillText("EN", 12, 12.5);
            } else {
                ctx.font = "14px 'Sarasa Gothic SC', sans-serif";
                ctx.fillText("中", 12, 12.5);
            }
        } else if (drawKey === "splayer") {
            // 实心盘原直径 18 格最显大，收 16 格
            ctx.beginPath();
            ctx.arc(12, 12, 8, 0, Math.PI * 2);
            ctx.fill();
            // 音符用底色镂空（原图白音符），随盘同比例收
            ctx.fillStyle = bgColor;
            ctx.fillRect(13.5, 6.5, 2, 9);
            ctx.fillRect(14, 6.5, 5.5, 3.5);
            ctx.strokeStyle = bgColor;
            ctx.lineWidth = 2.5;
            ctx.save();
            ctx.translate(11, 16);
            ctx.scale(3 / 2.5, 1);
            ctx.beginPath();
            ctx.arc(0, 0, 2.5, 0, Math.PI * 2);
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
        }
    }
}
