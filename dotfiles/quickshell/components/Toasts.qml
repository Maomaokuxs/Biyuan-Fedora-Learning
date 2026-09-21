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
            // 客户端兜底过期：server 端过期不可靠（常驻不走），>0 按它来，
            // <0（server 默认）给 8s，==0 常驻不管。delegate 销毁时 timer 同灭，
            // 与 server 真过期 double-dismiss 互不干扰。
            // 注意：到手的值是毫秒（文档写秒是错的，3000 按秒算就是 50 分钟），
            // >1000 的当毫秒除以 1000。
            Timer {
                property real timeoutSecs: {
                    var t = modelData.expireTimeout;
                    if (t > 1000)
                        return t / 1000;
                    return t;
                }
                interval: (timeoutSecs > 0 ? timeoutSecs : 8) * 1000
                running: timeoutSecs !== 0
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
