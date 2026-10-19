import QtQuick
import Quickshell.Widgets

// 边栏壁纸卡：大图预览 + 名称 + hellwal 四色点
ClippingRectangle {
    id: root
    property var theme
    property string wallUrl: ""
    property string wallName: ""
    property color wallBg: "#1e1e2e"
    property color wallFg: "#ffffff"
    property color wallAccent: "#89b4fa"
    property color wallMuted: "#45475a"
    signal clicked

    width: 400; height: 224; radius: 12
    color: theme ? theme.mediaBg : "#333"

    Image {
        width: parent.width; height: 180
        source: root.wallUrl
        fillMode: Image.PreserveAspectCrop
        asynchronous: true; cache: true
    }
    Row {
        width: parent.width
        anchors { bottom: parent.bottom; left: parent.left; right: parent.right; margins: 12 }
        height: 32; spacing: 8
        Text {
            width: parent.width - 4*22 - 4*8
            text: root.wallName
            font.pixelSize: 13; color: theme ? theme.fg : "white"
            elide: Text.ElideRight
            verticalAlignment: Text.AlignVCenter; height: parent.height
        }
        Repeater {
            model: [root.wallBg, root.wallFg, root.wallAccent, root.wallMuted]
            Rectangle {
                required property color modelData
                width: 22; height: 22; radius: 11
                color: modelData
                border.width: 1; border.color: "#ffffff33"
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
    MouseArea { anchors.fill: parent; onClicked: root.clicked() }
}
