import QtCore
import QtQuick
import Quickshell.Io
import Quickshell.Widgets

// 壁纸选择器：overlay 承载。缩略图网格读 ~/Pictures/wallpapers，
// 点选调 theme-sync.sh（hellwal 全链路不变），随机键接 wallpaper.sh。
// 当前壁纸（~/.cache/by-mgr/last-wallpaper）描边高亮。
Item {
    id: root
    property var theme
    signal requestClose

    width: 560
    height: 480
    implicitWidth: 560
    implicitHeight: 480

    // 注意：StandardPaths 回来的是 file:// 开头的 URL，不是裸路径，拼 URL 别再加前缀
    property string wallDir: StandardPaths.writableLocation(StandardPaths.PicturesLocation) + "/wallpapers"
    property string current: ""
    // 文件列表：FolderListModel 在此机上读不出数，改 Process ls（Workspaces 同款可靠模式）
    property var wallFiles: []

    function reloadWalls() {
        root.wallFiles = [];
        lsProc.running = true;
    }

    function refreshCurrent() {
        curProc.running = true;
    }
    function styleName(id: string) {
        if (id === "fade")
            return "淡入";
        if (id === "off")
            return "关闭";
        if (id === "random")
            return "随机";
        if (id === "wipe")
            return "横扫";
        if (id === "outside")
            return "反波";
        if (id === "twinkle")
            return "闪烁";
        return "追逐波";
    }
    function styleValid(id: string) {
        return id === "wave" || id === "fade" || id === "off" || id === "random" || id === "wipe" || id === "outside" || id === "twinkle";
    }
    function refreshAll() {
        root.reloadWalls();
        root.refreshCurrent();
        transProc.running = true;
    }
    // 过渡风格落盘（~/.cache/by-mgr/qs-transition），打开卡即读回
    Process {
        id: transProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/qs-transition 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (root.styleValid(t))
                    UiState.transitionStyle = t;
            }
        }
    }
    onVisibleChanged: { if (visible) root.refreshAll(); }
    Component.onCompleted: root.refreshAll()

    Process {
        id: lsProc
        // wallthumbs.sh list：逐行 {name,url,thumb}，缩略图走
        // ~/.cache/by-mgr/wallthumbs/<stat-id>.jpg（stat 口径与 theme-sync 一致，
        // 存在即最新）；边生成边吐，网格渐进加载。命中缓存时 32 张约 0.16s。
        command: ["bash", "-c", "bash " + Exec.scriptDir + "/wallthumbs.sh list"]
        stdout: SplitParser {
            splitMarker: "\n"
            onRead: data => {
                try {
                    var j = JSON.parse(data);
                    if (j.name && j.url)
                        root.wallFiles = root.wallFiles.concat([{ name: j.name, url: j.url, thumb: j.thumb || j.url }]);
                } catch (e) {}
            }
        }
    }

    Process {
        id: curProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/last-wallpaper 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: { root.current = this.text.trim(); }
        }
    }

    function applyWall(fileUrl: string) {
        var p = String(fileUrl).replace(/^file:\/\//, "");
        Exec.sh('bash ~/.config/niri/scripts/theme-sync.sh "' + p + '"');
        refreshTimer.restart();
    }
    function applyCurrent() {
        if (grid.currentIndex >= 0 && grid.currentIndex < root.wallFiles.length)
            root.applyWall(String(root.wallFiles[grid.currentIndex].url));
    }
    function snapToCurrent() {
        if (root.current === "")
            return;
        for (var i = 0; i < root.wallFiles.length; i++) {
            var u = String(root.wallFiles[i].url);
            if ("file://" + root.current === u || root.current === u.replace(/^file:\/\//, "")) {
                grid.currentIndex = i;
                grid.positionViewAtIndex(i, GridView.Center);
                break;
            }
        }
    }
    Timer {
        id: refreshTimer
        interval: 1500
        onTriggered: root.refreshCurrent()
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
                    text: "壁纸"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 14
                    font.bold: true
                    color: root.theme.fg
                    width: parent.width - 120
                    elide: Text.ElideRight
                }
                Text {
                    text: root.wallFiles.length + " 张"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.muted
                    width: 52
                    horizontalAlignment: Text.AlignRight
                }
                Text {
                    text: "随机"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.fg
                    width: 34
                    horizontalAlignment: Text.AlignRight
                    MouseArea {
                        anchors.fill: parent
                        anchors.margins: -6
                        onClicked: {
                            Exec.sh("bash ~/.config/niri/scripts/wallpaper.sh");
                            root.refreshTimer.restart();
                        }
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

            // 过渡动画下拉框：当前追逐波/淡入/关闭三档保留，选择落盘
            // z 必须设在与网格同一层（本 Row），写在浮层自己身上盖不住网格
            Row {
                id: transRow
                width: parent.width
                spacing: 8
                z: transBox.dropOpen ? 100 : 0
                Text {
                    text: "过渡"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 12
                    color: root.theme.muted
                    anchors.verticalCenter: parent.verticalCenter
                }
                Item {
                    id: transBox
                    width: 110
                    height: 28
                    property bool dropOpen: false
                    Rectangle {
                        anchors.fill: parent
                        radius: 8
                        color: "transparent"
                        border.color: root.theme.muted
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: root.styleName(UiState.transitionStyle) + " ▾"
                            font.family: root.theme.fontFamily
                            font.pixelSize: 12
                            color: root.theme.fg
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: transBox.dropOpen = !transBox.dropOpen
                        }
                    }
                    // 零占位浮层：不参与 Row 排布，盖在网格上
                    Item {
                        width: 0
                        height: 0
                        Rectangle {
                            visible: transBox.dropOpen
                            x: 0
                            y: 32
                            z: 100
                            width: 110
                            height: 7 * 30 + 12
                            radius: 8
                            color: root.theme.bg
                            border.color: root.theme.muted
                            border.width: 1
                            Column {
                                anchors.fill: parent
                                anchors.margins: 6
                                spacing: 0
                                Repeater {
                                    // 前两位固定：关闭、随机；后面再加新的往后排
                                    model: [{ id: "off", name: "关闭" }, { id: "random", name: "随机" }, { id: "wave", name: "追逐波" }, { id: "fade", name: "淡入" }, { id: "wipe", name: "横扫" }, { id: "outside", name: "反波" }, { id: "twinkle", name: "闪烁" }]
                                    Rectangle {
                                        required property var modelData
                                        width: 98
                                        height: 30
                                        radius: 6
                                        color: UiState.transitionStyle === modelData.id ? root.theme.accent : "transparent"
                                        Text {
                                            anchors.centerIn: parent
                                            text: modelData.name
                                            font.family: root.theme.fontFamily
                                            font.pixelSize: 12
                                            color: UiState.transitionStyle === modelData.id ? root.theme.clockFg : root.theme.fg
                                        }
                                        MouseArea {
                                            anchors.fill: parent
                                            onClicked: {
                                                UiState.transitionStyle = modelData.id;
                                                Exec.sh("printf '" + modelData.id + "' > ~/.cache/by-mgr/qs-transition");
                                                transBox.dropOpen = false;
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // 缩略图网格（取色仍由 theme-sync 接管，这里只管选）
            // 圆角预览图：无底色框，ClippingRectangle 直接裁圆角；
            // 方向键移动光标（highlight），回车/空格应用，Esc 关闭
            GridView {
                id: grid
                width: parent.width
                height: parent.height - 34
                clip: true
                cellWidth: Math.floor(width / 3)
                cellHeight: 108
                model: root.wallFiles
                focus: true
                keyNavigationWraps: true
                highlightMoveDuration: 150
                // 选中项高亮底框：铺满整个格子，比预览图大一圈
                highlight: Rectangle {
                    radius: 14
                    color: root.theme.accent
                }
                Keys.onReturnPressed: root.applyCurrent()
                Keys.onSpacePressed: root.applyCurrent()
                Keys.onEscapePressed: root.requestClose()
                delegate: Item {
                    required property var modelData
                    required property int index
                    width: grid.cellWidth
                    height: grid.cellHeight
                    // 圆角预览图，无文件名；当前壁纸 fg 描边
                    ClippingRectangle {
                        anchors.fill: parent
                        anchors.margins: 6
                        radius: 12
                        color: "transparent"
                        property bool isThumbCurrent: ("file://" + root.current === String(modelData.url)
                            || root.current === String(modelData.url).replace(/^file:\/\//, ""))
                        border.color: isThumbCurrent ? root.theme.fg : "transparent"
                        border.width: isThumbCurrent ? 2 : 0
                        Image {
                            anchors.fill: parent
                            source: modelData.thumb
                            sourceSize.width: 320
                            sourceSize.height: 200
                            asynchronous: true
                            cache: true
                            smooth: true
                            mipmap: true
                            fillMode: Image.PreserveAspectCrop
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            grid.currentIndex = index;
                            root.applyWall(modelData.url);
                        }
                    }
                }
                // 当前壁纸滚入视野并作为键盘起点
                onCountChanged: root.snapToCurrent()
            }
        }
    }
}
