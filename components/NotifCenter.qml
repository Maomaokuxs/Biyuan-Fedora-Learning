import QtQuick
import Quickshell.Services.Notifications

// 通知中心浮窗：历史列表 + 清空。overlay 承载。
Item {
    id: root
    property var theme
    signal requestClose

    width: 420
    height: 480
    implicitWidth: 420
    implicitHeight: 480

    function fmtTime(d) {
        var t = d instanceof Date ? d : new Date(d);
        return String(t.getHours()).padStart(2, "0") + ":" + String(t.getMinutes()).padStart(2, "0");
    }

    Rectangle {
        anchors.fill: parent
        radius: 20
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1
        clip: true

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 10

            Row {
                width: parent.width
                Text {
                    text: "通知"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    color: root.theme.fg
                    width: parent.width - 120
                    elide: Text.ElideRight
                }
                Text {
                    text: Notifs.history.length + " 条"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.muted
                    width: 52
                    horizontalAlignment: Text.AlignRight
                }
                Text {
                    text: "清空"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.fg
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: Notifs.clearHistory()
                    }
                }
                Text {
                    text: "✕"
                    font.pixelSize: 13
                    color: root.theme.muted
                    width: 14
                    horizontalAlignment: Text.AlignRight
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: root.requestClose()
                    }
                }
            }

            Text {
                visible: Notifs.history.length === 0
                width: parent.width
                text: "暂无通知"
                font.family: root.theme.fontFamily
                font.pixelSize: 13
                color: root.theme.muted
                horizontalAlignment: Text.AlignHCenter
            }

            ListView {
                width: parent.width
                height: parent.height - 34
                clip: true
                spacing: 6
                model: Notifs.history
                delegate: Rectangle {
                    required property var modelData
                    required property int index
                    width: ListView.view.width
                    height: rowCol.implicitHeight + 16
                    radius: 10
                    color: Qt.alpha(root.theme.accent, 0.25)
                    Column {
                        id: rowCol
                        anchors.left: parent.left
                        anchors.right: parent.right
                        anchors.top: parent.top
                        anchors.margins: 8
                        spacing: 2
                        Text {
                            width: parent.width
                            text: UiState.cleanText(modelData.summary) || "(无标题)"
                            font.family: root.theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: root.theme.fg
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            visible: UiState.cleanText(modelData.body) !== ""
                            text: UiState.cleanText(modelData.body)
                            font.family: root.theme.fontFamily
                            font.pixelSize: 12
                            color: root.theme.fg
                            wrapMode: Text.Wrap
                            maximumLineCount: 3
                            elide: Text.ElideRight
                        }
                        Text {
                            width: parent.width
                            text: (modelData.app || "") + " · " + root.fmtTime(modelData.time)
                            font.family: root.theme.fontFamily
                            font.pixelSize: 10
                            color: root.theme.muted
                        }
                    }
                }
            }
        }
    }
}
