import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Io

// 天气下拉面板（内容/排版 only；开合动画在 PopupReveal，宿主在 shell.qml）。
// 数据只读 ~/.cache/by-mgr/weather.json（weather.py 写：sojson 主数据
// + Open-Meteo 逐小时），与胶囊共用同一份缓存，两边永远一致。
// FileView 盯变化自动补刷；打开瞬间宿主还会调 reload() 兜底。
// 配色一律绑 theme 变量，不写死。
Item {
    id: root
    property var theme

    width: 372
    implicitHeight: col.implicitHeight + 28

    property var wdata: ({})
    readonly property var cur: (wdata && wdata.current) || ({})
    readonly property var today: (wdata && wdata.today) || ({})
    readonly property var hourly: (wdata && wdata.hourly) || []
    readonly property var days: ((wdata && wdata.forecast) || []).slice(0, 7)
    readonly property bool hasCur: !!(wdata && wdata.current)

    readonly property string subLine: {
        var p = [];
        if (cur.feels !== null && cur.feels !== undefined)
            p.push("体感 " + cur.feels + "°");
        if (cur.humidity !== null && cur.humidity !== undefined)
            p.push("湿度 " + cur.humidity + "%");
        if (cur.fx)
            p.push(cur.fx + (cur.fl || ""));
        if (today.sunrise)
            p.push("日出 " + today.sunrise);
        if (today.sunset)
            p.push("日落 " + today.sunset);
        return p.join(" · ");
    }
    readonly property string tipLine: (wdata && wdata.notice) ? wdata.notice : ((wdata && wdata.ganmao) || "")

    function deg(v) {
        return (v === null || v === undefined) ? "–" : Math.round(v) + "°";
    }
    function reload() {
        try {
            var j = JSON.parse(wview.text());
            if (j && (j.current || j.text))
                root.wdata = j;
        } catch (e) {}
        curve.requestPaint();
    }

    FileView {
        id: wview
        path: Quickshell.env("HOME") + "/.cache/by-mgr/weather.json"
        watchChanges: true
        onLoaded: root.reload()
        onFileChanged: root.reload()
    }
    Component.onCompleted: root.reload()
    onHourlyChanged: curve.requestPaint()

    Rectangle {
        anchors.fill: parent
        radius: 16
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
    }
    // 吃掉面板内点击：避免穿透到宿主背景层、被当成「点面板外」关掉
    MouseArea { anchors.fill: parent }

    Column {
        id: col
        anchors.fill: parent
        anchors.margins: 14
        spacing: 10

        // 无富数据（首次拉取前/兜底源）时的占位
        Text {
            visible: !root.hasCur
            width: parent.width
            text: "天气数据加载中…"
            font.family: root.theme.fontFamily
            font.pixelSize: 13
            color: root.theme.muted
            horizontalAlignment: Text.AlignHCenter
        }

        // ---- 头部：城市 + 大温度 + 类型，右侧空气质量 ----
        RowLayout {
            visible: root.hasCur
            width: parent.width
            spacing: 10

            Column {
                Layout.fillWidth: true
                spacing: 2
                Row {
                    spacing: 6
                    Text {
                        text: (root.wdata.city || "")
                        font.family: root.theme.fontFamily
                        font.pixelSize: 14
                        font.bold: true
                        color: root.theme.fg
                    }
                    Text {
                        anchors.bottom: parent.bottom
                        text: root.wdata.updated ? ("更新 " + root.wdata.updated) : ""
                        font.family: root.theme.fontFamily
                        font.pixelSize: 10
                        color: root.theme.muted
                    }
                }
                Row {
                    spacing: 8
                    Text {
                        text: root.days.length > 0 ? root.days[0].icon : ""
                        font.family: root.theme.fontFamily
                        font.pixelSize: 30
                        color: root.theme.fg
                    }
                    Text {
                        text: root.deg(root.cur.temp)
                        font.family: root.theme.fontFamily
                        font.pixelSize: 38
                        font.bold: true
                        color: root.theme.fg
                    }
                    Column {
                        anchors.bottom: parent.bottom
                        anchors.bottomMargin: 5
                        spacing: 1
                        Text {
                            text: root.cur.type || ""
                            font.family: root.theme.fontFamily
                            font.pixelSize: 14
                            color: root.theme.fg
                        }
                        Text {
                            text: root.deg(root.today.low) + " ~ " + root.deg(root.today.high)
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            color: root.theme.muted
                        }
                    }
                }
            }

            Column {
                visible: !!root.cur.quality
                Layout.alignment: Qt.AlignTop | Qt.AlignRight
                spacing: 4
                Rectangle {
                    anchors.right: parent.right
                    radius: 9
                    height: 22
                    width: badgeText.implicitWidth + 16
                    color: Qt.alpha(root.theme.accent, 0.20)
                    Text {
                        id: badgeText
                        anchors.centerIn: parent
                        text: "空气 " + root.cur.quality + ((root.today.aqi !== null && root.today.aqi !== undefined) ? " · AQI " + root.today.aqi : "")
                        font.family: root.theme.fontFamily
                        font.pixelSize: 11
                        color: root.theme.fg
                    }
                }
                Text {
                    anchors.right: parent.right
                    visible: root.cur.pm25 !== null && root.cur.pm25 !== undefined
                    text: "PM2.5 " + Math.round(root.cur.pm25 || 0) + " · PM10 " + Math.round(root.cur.pm10 || 0)
                    font.family: root.theme.fontFamily
                    font.pixelSize: 10
                    color: root.theme.muted
                }
            }
        }

        // ---- 小字信息行：体感/湿度/风/日出日落 ----
        Text {
            visible: root.hasCur && root.subLine !== ""
            width: parent.width
            text: root.subLine
            font.family: root.theme.fontFamily
            font.pixelSize: 11
            color: root.theme.muted
            elide: Text.ElideRight
        }

        Rectangle {
            visible: root.hasCur && root.hourly.length >= 2
            width: parent.width
            height: 1
            color: Qt.alpha(root.theme.muted, 0.35)
        }

        // ---- 逐小时曲线 ----
        RowLayout {
            visible: root.hourly.length >= 2
            width: parent.width
            Text {
                Layout.fillWidth: true
                text: "未来 24 小时"
                font.family: root.theme.fontFamily
                font.pixelSize: 12
                font.bold: true
                color: root.theme.fg
            }
            Text {
                text: "下方 % 为降雨概率"
                font.family: root.theme.fontFamily
                font.pixelSize: 10
                color: root.theme.muted
            }
        }
        Canvas {
            id: curve
            visible: root.hourly.length >= 2
            width: parent.width
            height: 106
            onWidthChanged: requestPaint()
            onPaint: {
                var ctx = getContext("2d");
                ctx.reset();
                var pts = root.hourly;
                if (!pts || pts.length < 2)
                    return;
                var W = width, H = height;
                var topPad = 20, botPad = 34;
                var min = Infinity, max = -Infinity, i, v;
                for (i = 0; i < pts.length; i++) {
                    v = Number(pts[i].temp);
                    if (isNaN(v))
                        continue;
                    if (v < min) min = v;
                    if (v > max) max = v;
                }
                if (min === Infinity)
                    return;
                if (max - min < 2) { max += 1; min -= 1; } else { max += 0.6; min -= 0.6; }
                var iw = W - 12;
                function X(i) { return 6 + iw * i / (pts.length - 1); }
                function Y(v) { return topPad + (max - v) / (max - min) * (H - topPad - botPad); }
                function tracePath() {
                    ctx.beginPath();
                    ctx.moveTo(X(0), Y(Number(pts[0].temp)));
                    for (var j = 1; j < pts.length - 1; j++) {
                        var xc = (X(j) + X(j + 1)) / 2;
                        var yc = (Y(Number(pts[j].temp)) + Y(Number(pts[j + 1].temp))) / 2;
                        ctx.quadraticCurveTo(X(j), Y(Number(pts[j].temp)), xc, yc);
                    }
                    ctx.lineTo(X(pts.length - 1), Y(Number(pts[pts.length - 1].temp)));
                }
                // 曲线下填充
                tracePath();
                ctx.lineTo(X(pts.length - 1), H - botPad);
                ctx.lineTo(X(0), H - botPad);
                ctx.closePath();
                ctx.fillStyle = Qt.alpha(root.theme.accent, 0.12);
                ctx.fill();
                // 曲线本体
                tracePath();
                ctx.strokeStyle = root.theme.accent;
                ctx.lineWidth = 2;
                ctx.lineJoin = "round";
                ctx.lineCap = "round";
                ctx.stroke();
                // 数据点
                ctx.fillStyle = root.theme.fg;
                for (i = 0; i < pts.length; i++) {
                    ctx.beginPath();
                    ctx.arc(X(i), Y(Number(pts[i].temp)), 1.8, 0, Math.PI * 2);
                    ctx.fill();
                }
                // 首点（现在）描环
                ctx.beginPath();
                ctx.arc(X(0), Y(Number(pts[0].temp)), 4, 0, Math.PI * 2);
                ctx.strokeStyle = root.theme.fg;
                ctx.lineWidth = 1.5;
                ctx.stroke();
                // 标签：每 3 小时一组（温度/时刻/降雨概率）+ 末点温度
                ctx.textAlign = "center";
                ctx.font = "10px '" + root.theme.fontFamily + "'";
                for (i = 0; i < pts.length; i++) {
                    var labeled = (i % 3 === 0);
                    if (labeled || i === pts.length - 1) {
                        ctx.fillStyle = root.theme.fg;
                        ctx.fillText(Math.round(Number(pts[i].temp)) + "°", X(i), Y(Number(pts[i].temp)) - 7);
                    }
                    if (labeled) {
                        ctx.fillStyle = root.theme.muted;
                        ctx.fillText(String(pts[i].t).substring(0, 2) + "时", X(i), H - botPad + 14);
                        var pop = Number(pts[i].pop) || 0;
                        if (pop > 0) {
                            ctx.fillStyle = root.theme.accent;
                            ctx.fillText(pop + "%", X(i), H - botPad + 27);
                        }
                    }
                }
            }
        }
        Text {
            visible: root.hasCur && root.hourly.length < 2
            width: parent.width
            text: "逐小时数据暂缺"
            font.family: root.theme.fontFamily
            font.pixelSize: 11
            color: root.theme.muted
            horizontalAlignment: Text.AlignHCenter
        }

        Rectangle {
            visible: root.days.length > 0
            width: parent.width
            height: 1
            color: Qt.alpha(root.theme.muted, 0.35)
        }

        // ---- 未来 7 天 ----
        Repeater {
            model: root.days
            delegate: RowLayout {
                width: parent ? parent.width : 372
                height: 24
                spacing: 8
                Text {
                    Layout.preferredWidth: 40
                    text: index === 0 ? "今天" : String(modelData.week || "").replace("星期", "周")
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.fg
                }
                Text {
                    Layout.preferredWidth: 40
                    text: String(modelData.ymd || "").substring(5).replace("-", "/")
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    color: root.theme.muted
                }
                Text {
                    Layout.preferredWidth: 24
                    text: modelData.icon || ""
                    font.family: root.theme.fontFamily
                    font.pixelSize: 15
                    color: root.theme.fg
                }
                Text {
                    Layout.fillWidth: true
                    text: modelData.type || ""
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.muted
                    elide: Text.ElideRight
                }
                Text {
                    text: root.deg(modelData.low) + " ~ " + root.deg(modelData.high)
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.fg
                }
            }
        }

        // ---- 生活提示 ----
        Text {
            visible: root.tipLine !== ""
            width: parent.width
            text: root.tipLine
            font.family: root.theme.fontFamily
            font.pixelSize: 11
            color: root.theme.muted
            elide: Text.ElideRight
        }
    }
}
