import QtQuick
import "../components" as Comp

// 可视化外壳：Pill（背景/hover/锚点/点击/主题）+ 模式 Loader。
// dance/spectrum 互斥实例化：不在台上的不建绑定、不跑采集、不占进程。
// off 切空窗（静默），暂停由各模式自行压平。
// 左键 toggle-music / 右键 toggle-lyric / 中键切效果卡，与原 CavaBar 一致。
Comp.Pill {
    id: root
    property var theme
    property string screenName: ""
    anchorKey: "vizAnchorX"
    anchorScreen: screenName
    // 背景恒定，hover 不反色（柱子墨水始终可见）
    normalBg: theme ? theme.mediaBg : "#a89a98"  // FALLBACK: theme 常在
    normalFg: theme ? theme.mediaBg : "#a89a98"
    fixedWidth: 104
    pillText: " "

    property string vizEff: Comp.UiState.vizEffect
    Loader {
        id: contentLoader
        anchors.fill: parent
        active: root.vizEff !== "off"
        source: root.vizEff === "spectrum" ? "SpectrumMeter.qml" : "DanceMeter.qml"
        onLoaded: {
            if (item)
                item.theme = root.theme;
        }
    }
    onThemeChanged: {
        if (contentLoader.item)
            contentLoader.item.theme = root.theme;
    }

    onLeftClicked: {
        Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music.sh");
    }
    onRightClicked: {
        Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-lyric.sh");
    }
    onMiddleClicked: Comp.UiState.toggleViz(root.screenName)
}
