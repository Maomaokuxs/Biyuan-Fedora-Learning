import QtQuick
import "../components" as Comp

// 可视化外壳：Pill（背景/hover/锚点/点击/主题）+ 模式 Loader。
// dance/spectrum 互斥实例化：不在台上的不建绑定、不跑采集、不占进程。
// off 切空窗（静默），暂停由各模式自行压平。
// 无播放器自动关闭：播放器都没了切空窗，来播放器恢复上次效果；暂停不断显隐；
// 只动内存状态，不碰落盘文件（qs-vizeffect 仍是用户手动选择）；
// 双屏两个实例逻辑幂等（写相同值），手动选非 off 则自动恢复取消。
// 左键音乐选单（rofi）/ 右键只藏后面的跟随者（尾闸，歌名留守）/ 中键切效果卡。
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
    // 整块显隐：播放器都没了整组折叠；总闸拉下同样折叠（含自己）；
    // 暂停留 baseline 在屏上（和其它音频模块一致）；
    // 播时必现（效果 off 则显示空窗，中键照常进选择卡）；
    // 尾闸只藏后面的跟随者，不管自己。效果开关只管内容。
    forceHidden: !root.hasPlayer || Comp.BarState.flagM

    property string vizEff: Comp.UiState.vizEffect
    // 显隐的门是有播放器（暂停也算）：暂停留 baseline 在屏上，只有人走茶凉才藏
    property bool hasPlayer: Comp.SpectrumState.hasPlayer
    function autoOffNow() {
        if (Comp.UiState.vizEffect !== "off") {
            Comp.UiState.vizEffectSaved = Comp.UiState.vizEffect;
            Comp.UiState.vizEffectAutoOff = true;
            Comp.UiState.vizEffect = "off";
        }
    }
    function autoRestore() {
        if (Comp.UiState.vizEffectAutoOff && Comp.UiState.vizEffect === "off") {
            Comp.UiState.vizEffectAutoOff = false;
            if (Comp.UiState.vizEffectSaved !== "" && Comp.UiState.vizEffectSaved !== "off")
                Comp.UiState.vizEffect = Comp.UiState.vizEffectSaved;
        }
    }
    onHasPlayerChanged: {
        if (!root.hasPlayer)
            root.autoOffNow();
        else
            root.autoRestore();
    }
    Component.onCompleted: {
        if (!root.hasPlayer)
            root.autoOffNow();
    }
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
        Comp.Exec.sh("bash ~/.config/rofi/scripts/music-menu.sh");
    }
    onRightClicked: {
        // 只藏跟随者：翻尾闸（播放键/歌词），自己和歌名留守
        Comp.Exec.sh("bash " + Comp.Exec.commonDir + "/toggle-music-tail.sh");
        Comp.BarState.refresh();
    }
    onMiddleClicked: Comp.UiState.toggleViz(root.screenName)
}
