import QtQuick

Rectangle {
    id: root
    property var entries: []
    property string currentPath: ""
    property color backgroundColor: "#1a2019"
    property color foregroundColor: "#d8e2d0"
    property color accentColor: "#a3be8c"
    property color mutedColor: "#5c6656"
    signal applyRequested(string url)
    signal randomRequested()
    signal closeRequested()

    function isCurrent(url) {
        var value = String(url || "");
        return "file://" + root.currentPath === value || root.currentPath === value.replace(/^file:\/\//, "");
    }

    function currentEntry() {
        for (var i = 0; i < root.entries.length; i++) {
            if (root.isCurrent(root.entries[i].url))
                return root.entries[i];
        }
        return root.entries.length > 0 ? root.entries[0] : null;
    }

    function syncCurrentIndex() {
        for (var i = 0; i < root.entries.length; i++) {
            if (root.isCurrent(root.entries[i].url)) {
                list.currentIndex = i;
                return;
            }
        }
        if (root.entries.length > 0)
            list.currentIndex = 0;
    }

    onEntriesChanged: syncCurrentIndex()
    onCurrentPathChanged: syncCurrentIndex()
    Component.onCompleted: {
        syncCurrentIndex();
        forceActiveFocus();
    }
    onVisibleChanged: {
        if (visible) {
            syncCurrentIndex();
            forceActiveFocus();
        }
    }

    width: 600
    height: 450
    radius: 18
    color: Qt.alpha(backgroundColor, 0.97)
    border.width: 1
    border.color: Qt.alpha(accentColor, 0.6)
    opacity: visible ? 1 : 0
    scale: visible ? 1 : 0.96
    transformOrigin: Item.Center
    Behavior on opacity { NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on scale { NumberAnimation { duration: 220; easing.type: Easing.OutBack } }
    focus: true
    activeFocusOnTab: true

    Keys.onPressed: event => {
        if (event.key === Qt.Key_Up) {
            list.currentIndex = Math.max(0, list.currentIndex - 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Down) {
            list.currentIndex = Math.min(list.count - 1, list.currentIndex + 1);
            event.accepted = true;
        } else if (event.key === Qt.Key_Return || event.key === Qt.Key_Enter) {
            if (list.currentIndex >= 0 && list.currentIndex < list.count)
                root.applyRequested(root.entries[list.currentIndex].url);
            event.accepted = true;
        } else if (event.key === Qt.Key_Escape) {
            root.closeRequested();
            event.accepted = true;
        }
    }

    MouseArea {
        anchors.fill: parent
        onClicked: mouse => mouse.accepted = true
    }

    Column {
        anchors.fill: parent
        anchors.margins: 18
        spacing: 10

        Row {
            width: parent.width
            height: 30
            spacing: 12

            Text {
                text: "壁纸"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 15
                font.bold: true
                color: root.foregroundColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: root.entries.length + " 张"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 11
                color: root.mutedColor
                anchors.verticalCenter: parent.verticalCenter
            }

            Text {
                text: "随机一张"
                font.family: "JetBrainsMono Nerd Font"
                font.pixelSize: 12
                color: root.accentColor
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -5
                    onClicked: root.randomRequested()
                }
            }

            Item {
                width: 1
                height: 1
            }

            Text {
                text: "✕"
                font.pixelSize: 13
                color: root.mutedColor
                anchors.verticalCenter: parent.verticalCenter
                MouseArea {
                    anchors.fill: parent
                    anchors.margins: -8
                    onClicked: root.closeRequested()
                }
            }
        }

        Row {
            width: parent.width
            height: 370
            spacing: 12

            Rectangle {
                width: 360
                height: 370
                radius: 13
                color: Qt.alpha(root.backgroundColor, 0.72)
                border.width: 1
                border.color: Qt.alpha(root.mutedColor, 0.45)
                clip: true

                Image {
                    id: previewImage
                    anchors.fill: parent
                    source: root.currentEntry() ? root.currentEntry().url : ""
                    sourceSize.width: 1600
                    sourceSize.height: 1000
                    asynchronous: true
                    cache: true
                    smooth: true
                    fillMode: Image.PreserveAspectCrop
                    opacity: 1
                    onSourceChanged: {
                        opacity = 0;
                        previewFade.restart();
                    }
                    Behavior on opacity { NumberAnimation { duration: 220; easing.type: Easing.OutCubic } }
                }

                Timer {
                    id: previewFade
                    interval: 80
                    onTriggered: previewImage.opacity = 1
                }

                Rectangle {
                    anchors.left: parent.left
                    anchors.right: parent.right
                    anchors.bottom: parent.bottom
                    height: 30
                    color: Qt.alpha(root.backgroundColor, 0.82)

                    Text {
                        anchors.left: parent.left
                        anchors.bottom: parent.bottom
                        anchors.margins: 9
                        text: "当前壁纸"
                        font.family: "JetBrainsMono Nerd Font"
                        font.pixelSize: 11
                        font.bold: true
                        color: root.foregroundColor
                    }
                }
            }

            Column {
                width: 190
                height: 370
                spacing: 10

                Text {
                    text: "选择壁纸"
                    font.family: "JetBrainsMono Nerd Font"
                    font.pixelSize: 11
                    font.bold: true
                    color: root.mutedColor
                }

                ListView {
                    id: list
                    width: parent.width
                    height: 330
                    clip: true
                    spacing: 6
                    model: root.entries
                    onCurrentIndexChanged: {
                        if (currentIndex >= 0)
                            positionViewAtIndex(currentIndex, ListView.Contain);
                    }

                    delegate: Item {
                        required property var modelData
                        required property int index
                        width: list.width
                        height: 62

                        Rectangle {
                            anchors.fill: parent
                            radius: 8
                             color: Qt.alpha(root.backgroundColor, 0.55)
                             border.width: root.isCurrent(modelData.url) || index === list.currentIndex ? 2 : 1
                             border.color: index === list.currentIndex ? root.accentColor : Qt.alpha(root.mutedColor, 0.4)
                             scale: thumbHover.containsMouse ? 1.04 : 1
                             Behavior on scale { NumberAnimation { duration: 130; easing.type: Easing.OutCubic } }
                             Behavior on border.color { ColorAnimation { duration: 140 } }
                             clip: true


                            Image {
                                anchors.fill: parent
                                anchors.margins: 2
                                source: modelData.thumb
                                sourceSize.width: 260
                                sourceSize.height: 100
                                asynchronous: true
                                cache: true
                                smooth: true
                                fillMode: Image.PreserveAspectCrop
                            }
                        }

                        MouseArea {
                            id: thumbHover
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: {
                                list.currentIndex = index;
                                root.applyRequested(modelData.url);
                            }
                        }
                    }
                }
            }
        }
    }
}
