import QtQuick
import QtQuick.Layouts

// 左侧工具组：8 个图标合并到一个胶囊里，保留各自点击/右键
Rectangle {
    id: root
    property var theme
    property string screenName
    property bool forceHidden: false
    property var barState
    property var exec
    property var uiState
    property var icons

    visible: !forceHidden
    Layout.preferredWidth: visible ? contentRow.implicitWidth + 20 : 0
    Layout.preferredHeight: 32
    height: 32
    radius: 10
    color: theme.accent

    RowLayout {
        id: contentRow
        anchors.centerIn: parent
        spacing: 8

        // 录制
        Text {
            text: barState.recT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: (barState.recC === "recording" || barState.recC === "kernel" || barState.recC === "many" || barState.recC === "inhibited") ? theme.clockFg : theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        exec.sh("pkill -INT -f gpu-screen-recorder");
                    } else {
                        exec.sh("~/.config/rofi/scripts/recorder.sh");
                    }
                    barState.refresh();
                }
            }
        }
        // 截图
        Text {
            text: barState.shotT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: exec.sh("bash " + exec.commonDir + "/screenshot.sh")
            }
        }
        // 取色
        Text {
            text: barState.pickT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: exec.sh("bash " + exec.commonDir + "/pick-color.sh")
            }
        }
        // 剪贴板
        Text {
            text: barState.clipT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: function(mouse) {
                    if (mouse.button === Qt.RightButton) {
                        exec.sh("copyq eval \\\"clear()\\\" 2>/dev/null; notify-send \\\"剪贴板\\\" \\\"已清空\\\"");
                    } else {
                        exec.sh("copyq toggle");
                    }
                }
            }
        }
        // 护眼
        Text {
            text: barState.gammaT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    exec.sh("bash " + exec.commonDir + "/gamma-toggle.sh");
                    barState.refreshOne("gamma", "bash " + exec.commonDir + "/gammastep.sh");
                }
            }
        }
        // 主题
        Text {
            text: barState.themeT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    exec.sh("bash ~/.config/niri/scripts/toggle-theme.sh");
                    barState.refresh();
                }
            }
        }
        // 壁纸
        Text {
            text: icons.wallpaper
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 17
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: uiState.toggleWallpaperPicker(screenName)
            }
        }
        // 显示器
        Text {
            text: barState.screenT
            font.family: "JetBrainsMono Nerd Font"
            font.pixelSize: 16
            color: theme.fg
            MouseArea {
                anchors.fill: parent
                cursorShape: Qt.PointingHandCursor
                onClicked: {
                    exec.sh("bash " + exec.commonDir + "/screen.sh menu");
                    barState.refresh();
                }
            }
        }
    }
}
