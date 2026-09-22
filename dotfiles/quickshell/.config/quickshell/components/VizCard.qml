import QtQuick
import Quickshell.Io

// 电平效果切换卡：由 shell.qml 的 overlay PanelWindow 承载（中键点电平条呼出）。
// 律动 / 声谱 / 关闭三档，选后即时生效 + 落盘记忆。
// dance 模式多一排编排选项（自动/四式/混合），切换走交叉淡化、不断层，同样落盘。
Item {
    id: root
    property var theme
    signal requestClose

    width: 480
    // 高度实算：dance 下内容 = 边距32 + 标题21 + 3×38效果行 + 标题20 + 4行格子144 + 5×8间距 = 371 → 取 375；
    // 格子 10 个 3 列排是 3+3+3+1 四行，之前按三行算少了 38，末行被裁
    height: UiState.vizEffect === "dance" ? 375 : 200
    implicitWidth: 480
    implicitHeight: UiState.vizEffect === "dance" ? 375 : 200

    function effectName(id: string) {
        if (id === "spectrum")
            return "声谱";
        if (id === "off")
            return "关闭";
        return "律动";
    }
    function effectDesc(id: string) {
        if (id === "spectrum")
            return "pw-record 直采 + FFT，真分频";
        if (id === "off")
            return "静默基线，不跑进程";
        return "程序编排跟响度走，零外部进程";
    }
    // 编排选项：0 自动，1-8 起伏/斜纹/呼吸/交错/脉冲/驼峰/闪烁/峭壁，9 混合（存值 -1/0-7/8）
    function patName(i: int) {
        return ["自动", "起伏", "斜纹", "呼吸", "交错", "脉冲", "驼峰", "闪烁", "峭壁", "混合"][i];
    }
    function refreshEffect() {
        effectProc.running = true;
        patProc.running = true;
    }

    Process {
        id: effectProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/qs-vizeffect 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var t = this.text.trim();
                if (t === "dance" || t === "spectrum" || t === "off")
                    UiState.vizEffect = t;
            }
        }
    }
    Process {
        id: patProc
        command: ["bash", "-c", "cat ~/.cache/by-mgr/qs-dancepattern 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                var n = parseInt(this.text.trim(), 10);
                if (n >= -1 && n <= 8)
                    UiState.dancePattern = n;
            }
        }
    }

    onVisibleChanged: { if (visible) root.refreshEffect(); }
    Component.onCompleted: root.refreshEffect()

    Rectangle {
        anchors.fill: parent
        radius: 14
        color: root.theme.bg
        border.color: root.theme.muted
        border.width: 1

        Column {
            anchors.fill: parent
            anchors.margins: 16
            spacing: 8

            Row {
                width: parent.width
                Text {
                    text: "可视化效果"
                    font.family: root.theme.fontFamily
                    font.pixelSize: 16
                    font.bold: true
                    color: root.theme.fg
                    width: parent.width - 14
                    elide: Text.ElideRight
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

            Repeater {
                model: [{ id: "dance", }, { id: "spectrum" }, { id: "off" }]
                Rectangle {
                    required property var modelData
                    width: parent.width
                    height: 38
                    radius: 10
                    color: UiState.vizEffect === modelData.id ? root.theme.accent : "transparent"
                    border.color: root.theme.muted
                    border.width: 1
                    Row {
                        anchors.fill: parent
                        anchors.leftMargin: 12
                        anchors.rightMargin: 12
                        spacing: 10
                        anchors.verticalCenter: parent.verticalCenter
                        Text {
                            text: root.effectName(modelData.id)
                            font.family: root.theme.fontFamily
                            font.pixelSize: 13
                            font.bold: true
                            color: UiState.vizEffect === modelData.id ? root.theme.clockFg : root.theme.fg
                            anchors.verticalCenter: parent.verticalCenter
                        }
                        Text {
                            text: root.effectDesc(modelData.id)
                            font.family: root.theme.fontFamily
                            font.pixelSize: 11
                            color: UiState.vizEffect === modelData.id ? root.theme.clockFg : root.theme.muted
                            anchors.verticalCenter: parent.verticalCenter
                            elide: Text.ElideRight
                        }
                    }
                    MouseArea {
                        anchors.fill: parent
                        onClicked: {
                            UiState.vizEffect = modelData.id;
                            Exec.sh("printf '" + modelData.id + "' > ~/.cache/by-mgr/qs-vizeffect");
                            root.requestClose();
                        }
                    }
                }
            }

            // 舞者编排：仅 dance 模式展开，点选即交叉淡化过去，卡片不关可连试
            Text {
                visible: UiState.vizEffect === "dance"
                text: "舞者编排"
                font.family: root.theme.fontFamily
                font.pixelSize: 15
                font.bold: true
                color: root.theme.fg
            }
            Grid {
                visible: UiState.vizEffect === "dance"
                columns: 3
                spacing: 8
                width: parent.width
                Repeater {
                    model: 10
                    Rectangle {
                        required property int index
                        width: (parent.width - 16) / 3
                        height: 30
                        radius: 8
                        color: UiState.dancePattern === index - 1 ? root.theme.accent : "transparent"
                        border.color: root.theme.muted
                        border.width: 1
                        Text {
                            anchors.centerIn: parent
                            text: root.patName(index)
                            font.family: root.theme.fontFamily
                            font.pixelSize: 12
                            color: UiState.dancePattern === index - 1 ? root.theme.clockFg : root.theme.fg
                        }
                        MouseArea {
                            anchors.fill: parent
                            onClicked: {
                                UiState.dancePattern = index - 1;
                                Exec.sh("printf '%s' " + (index - 1) + " > ~/.cache/by-mgr/qs-dancepattern");
                            }
                        }
                    }
                }
            }
        }
    }
}
