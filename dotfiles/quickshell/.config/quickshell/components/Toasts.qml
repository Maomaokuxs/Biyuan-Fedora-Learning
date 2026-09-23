import QtQuick
import Quickshell.Services.Notifications
import Quickshell.Widgets

// 右上 toast 栈：mako 样式（底/字/边框/圆角9/字体/超时），urgency 三档配色。
// 过期由 server 自动收（tracked 移除即消失），点击卡片手动 dismiss。
Column {
    id: root
    property var theme
    spacing: 8

    Repeater {
        model: Notifs.server.trackedNotifications.values.slice(-5)
        Rectangle {
            id: toastCard
            required property var modelData
            width: 380
            height: toastCol.implicitHeight + 24
            radius: 9
            // 客户端兜底过期：全部临时toast，无常驻——
            // expireTimeout 语义恒为毫秒：-1（server 默认）/0（永不过期）一律 5s；
            // 正值毫秒转秒，超 30s 按 30s 收（个别应用填 INT_MAX 级，等于常驻）。
            // 旧逻辑把 <=1000ms 当秒算（-t 1000 变 1000 秒），那就是"固定"的来源。
            Timer {
                property real timeoutSecs: {
                    var t = Number(modelData.expireTimeout);
                    if (!(t > 0))
                        return 5;
                    return Math.min(t / 1000, 30);
                }
                interval: timeoutSecs * 1000
                running: true
                onTriggered: modelData.dismiss()
            }
            color: modelData.urgency === NotificationUrgency.Critical ? root.theme.accent : root.theme.bg
            border.color: modelData.urgency === NotificationUrgency.Critical
                ? root.theme.fg
                : (modelData.urgency === NotificationUrgency.Low ? root.theme.muted : root.theme.accent)
            border.width: 2
            clip: true

            property color ink: modelData.urgency === NotificationUrgency.Critical ? root.theme.bg : root.theme.fg
            // 图标：-i 的内容在 image 里，appIcon 只是发送应用自己的图标。
            // 文件路径走 Image（限解码），主题名走 IconImage。
            property string iconSrc: modelData.image || modelData.appIcon || ""
            property bool iconIsPath: iconSrc.startsWith("/") || iconSrc.startsWith("file://")

            Row {
                anchors.left: parent.left
                anchors.right: parent.right
                anchors.top: parent.top
                anchors.margins: 12
                spacing: iconSrc !== "" ? 10 : 0

                Item {
                    width: iconSrc !== "" ? 44 : 0
                    height: 44
                    visible: iconSrc !== ""
                    Image {
                        anchors.fill: parent
                        visible: toastCard.iconIsPath
                        source: toastCard.iconIsPath ? toastCard.iconSrc : ""
                        sourceSize.width: 96
                        sourceSize.height: 96
                        asynchronous: true
                        cache: true
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                    }
                    IconImage {
                        anchors.centerIn: parent
                        visible: !toastCard.iconIsPath
                        implicitSize: 32
                        source: toastCard.iconIsPath ? "" : toastCard.iconSrc
                    }
                }

            Column {
                id: toastCol
                width: parent.width - (iconSrc !== "" ? 54 : 0)
                spacing: 4
                Text {
                    width: parent.width
                    text: UiState.cleanText(modelData.summary) || "(无标题)"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    font.bold: true
                    color: toastCard.ink
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: UiState.cleanText(modelData.body) !== ""
                    text: UiState.cleanText(modelData.body)
                    font.family: root.theme.fontFamily
                    font.pixelSize: 11
                    color: toastCard.ink
                    wrapMode: Text.Wrap
                    maximumLineCount: 4
                    elide: Text.ElideRight
                }
                Text {
                    width: parent.width
                    visible: UiState.cleanText(modelData.appName) !== ""
                    text: UiState.cleanText(modelData.appName)
                    font.family: root.theme.fontFamily
                    font.pixelSize: 10
                    color: toastCard.ink
                    opacity: 0.7
                    elide: Text.ElideRight
                }
                Row {
                    visible: modelData.actions && modelData.actions.length > 0
                    spacing: 8
                    Repeater {
                        model: modelData.actions
                        Text {
                            required property var modelData
                            text: "[" + (modelData.text || "打开") + "]"
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            font.underline: true
                            color: toastCard.ink
                            MouseArea {
                                anchors.fill: parent
                                onClicked: modelData.invoke()
                            }
                        }
                    }
                }
                }
            }
            MouseArea {
                anchors.fill: parent
                acceptedButtons: Qt.LeftButton
                onClicked: modelData.dismiss()
            }
        }
    }
}
