import QtQuick
import Quickshell
import Quickshell.Io

// 快捷开关组：Wi-Fi / 蓝牙 / 勿扰 / 护眼 / 飞行模式
Item {
    id: root
    property var theme
    property var exec

    property bool wifiOn: false
    property bool btOn: false
    property bool dndOn: false
    property bool eyeOn: false
    property bool planeOn: false

    implicitHeight: 48

    function refresh() {
        wifiProc.running = true
        btProc.running = true
        dndProc.running = true
        eyeProc.running = true
        planeProc.running = true
    }
    Component.onCompleted: refresh()

    Process {
        id: wifiProc
        command: ["bash", "-c", "gdbus call --system --dest org.freedesktop.NetworkManager --object-path /org/freedesktop/NetworkManager --method org.freedesktop.DBus.Properties.Get org.freedesktop.NetworkManager WirelessEnabled 2>/dev/null | grep -q true && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: { root.wifiOn = (this.text.trim() === "on") } }
    }
    Process {
        id: btProc
        command: ["bash", "-c", "bluetoothctl show 2>/dev/null | grep -q 'Powered: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: { root.btOn = (this.text.trim() === "on") } }
    }
    Process {
        id: dndProc
        command: ["bash", "-c", "makoctl mode 2>/dev/null | grep -q do-not-disturb && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: { root.dndOn = (this.text.trim() === "on") } }
    }
    Process {
        id: eyeProc
        command: ["bash", "-c", "pgrep -x gammastep >/dev/null && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: { root.eyeOn = (this.text.trim() === "on") } }
    }
    // 飞行模式：rfkill 全 block 即为开
    Process {
        id: planeProc
        command: ["bash", "-c", "rfkill list wifi 2>/dev/null | grep -q 'Soft blocked: yes' && echo on || echo off"]
        stdout: StdioCollector { onStreamFinished: { root.planeOn = (this.text.trim() === "on") } }
    }
    Process {
        id: wifiToggleProc
        onExited: function(exitCode, exitStatus) { root.confirm("wifi"); root.confirm("plane") }
    }
    Timer {
        id: confirmTimer
        interval: 800
        property string target: ""
        onTriggered: {
            if (target === "wifi") wifiProc.running = true
            else if (target === "bt") btProc.running = true
            else if (target === "dnd") dndProc.running = true
            else if (target === "eye") eyeProc.running = true
            else if (target === "plane") { planeProc.running = true; wifiProc.running = true; btProc.running = true }
        }
    }
    function confirm(which) { confirmTimer.target = which; confirmTimer.restart() }

    function toggleWifi(turning) {
        root.wifiOn = turning
        wifiToggleProc.command = ["gdbus", "call", "--system",
            "--dest", "org.freedesktop.NetworkManager",
            "--object-path", "/org/freedesktop/NetworkManager",
            "--method", "org.freedesktop.DBus.Properties.Set",
            "org.freedesktop.NetworkManager", "WirelessEnabled",
            turning ? "<true>" : "<false>"]
        wifiToggleProc.running = true
    }
    function toggleBt(turning) {
        root.btOn = turning
        root.exec.sh("bluetoothctl power " + (turning ? "on" : "off") + " >/dev/null 2>&1")
        root.confirm("bt")
    }
    // 飞行模式：开关 Wi-Fi 和蓝牙射频
    function togglePlane(turning) {
        root.planeOn = turning
        root.wifiOn = !turning
        root.btOn = !turning
        wifiToggleProc.command = ["gdbus", "call", "--system",
            "--dest", "org.freedesktop.NetworkManager",
            "--object-path", "/org/freedesktop/NetworkManager",
            "--method", "org.freedesktop.DBus.Properties.Set",
            "org.freedesktop.NetworkManager", "WirelessEnabled",
            turning ? "<false>" : "<true>"]
        wifiToggleProc.running = true
        root.exec.sh("bluetoothctl power " + (turning ? "off" : "on") + " >/dev/null 2>&1")
        root.confirm("plane")
    }

    // 5 个按钮：用 anchors 定位
    Rectangle {
        id: btnWifi
        anchors { left: parent.left; top: parent.top; bottom: parent.bottom }
        width: (parent.width - 48) / 5
        radius: 8
        color: root.wifiOn ? root.theme.accent : Qt.alpha(root.theme.accent, 0.18)
        Column { anchors.centerIn: parent; spacing: 1
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\uf1eb"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; color: root.wifiOn ? root.theme.bg : root.theme.fg }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "Wi-Fi"; font.pixelSize: 11; color: root.wifiOn ? root.theme.bg : root.theme.fg }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleWifi(!root.wifiOn)
        }
    }
    Rectangle {
        id: btnBt
        anchors { left: btnWifi.right; leftMargin: 12; top: parent.top; bottom: parent.bottom }
        width: (parent.width - 48) / 5
        radius: 8
        color: root.btOn ? root.theme.accent : Qt.alpha(root.theme.accent, 0.18)
        Column { anchors.centerIn: parent; spacing: 1
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\uf294"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; color: root.btOn ? root.theme.bg : root.theme.fg }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "蓝牙"; font.pixelSize: 11; color: root.btOn ? root.theme.bg : root.theme.fg }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: root.toggleBt(!root.btOn)
        }
    }
    Rectangle {
        id: btnDnd
        anchors { left: btnBt.right; leftMargin: 12; top: parent.top; bottom: parent.bottom }
        width: (parent.width - 48) / 5
        radius: 8
        color: root.dndOn ? root.theme.accent : Qt.alpha(root.theme.accent, 0.18)
        Column { anchors.centerIn: parent; spacing: 1
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\uf186"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; color: root.dndOn ? root.theme.bg : root.theme.fg }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "勿扰"; font.pixelSize: 11; color: root.dndOn ? root.theme.bg : root.theme.fg }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: {
                var turning = !root.dndOn
                root.dndOn = turning
                root.exec.sh("makoctl mode " + (turning ? "-a" : "-r") + " do-not-disturb >/dev/null 2>&1")
                root.confirm("dnd")
            }
        }
    }
    Rectangle {
        id: btnEye
        anchors { left: btnDnd.right; leftMargin: 12; top: parent.top; bottom: parent.bottom }
        width: (parent.width - 48) / 5
        radius: 8
        color: root.eyeOn ? root.theme.accent : Qt.alpha(root.theme.accent, 0.18)
        Column { anchors.centerIn: parent; spacing: 1
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\uf06e"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; color: root.eyeOn ? root.theme.bg : root.theme.fg }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "护眼"; font.pixelSize: 11; color: root.eyeOn ? root.theme.bg : root.theme.fg }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: {
                var turning = !root.eyeOn
                root.eyeOn = turning
                root.exec.sh("bash " + root.exec.commonDir + "/gamma-toggle.sh >/dev/null 2>&1")
                root.confirm("eye")
            }
        }
    }
    Rectangle {
        id: btnPlane
        anchors { right: parent.right; top: parent.top; bottom: parent.bottom }
        width: (parent.width - 48) / 5
        radius: 8
        color: root.planeOn ? root.theme.accent : Qt.alpha(root.theme.accent, 0.18)
        Column { anchors.centerIn: parent; spacing: 1
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "\uf072"; font.family: "JetBrainsMono Nerd Font"; font.pixelSize: 14; color: root.planeOn ? root.theme.bg : root.theme.fg }
            Text { anchors.horizontalCenter: parent.horizontalCenter; text: "飞行"; font.pixelSize: 11; color: root.planeOn ? root.theme.bg : root.theme.fg }
        }
        MouseArea {
            anchors.fill: parent; cursorShape: Qt.PointingHandCursor
            onClicked: root.togglePlane(!root.planeOn)
        }
    }
}
