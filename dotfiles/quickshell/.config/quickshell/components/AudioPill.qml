import QtQuick
import Quickshell.Io

// 音量 pill：wpctl 脚本轮询（Quickshell Pipewire 服务在新版 pipewire 下
// sink 永不 ready，原生绑定弃用；交互语义与旧版一致）。
ScriptPill {
    id: root
    property string screenName: ""
    anchorKey: "volAnchorX"
    anchorScreen: root.screenName

    baseBg: "#998c8c" // FALLBACK: Bar 必传
    baseFg: "#6a442f" // FALLBACK: Bar 必传

    execCmd: Exec.commonDir + "/audio.sh"
    pollInterval: 2000

    onLeftClicked: UiState.toggleVol(root.screenName)
    onRightClicked: Exec.run(["pavucontrol"])
    onMiddleClicked: {
        Exec.run(["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"]);
        root.refresh();
    }
    onScrollUp: {
        Exec.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.05+", "-l", "1.0"]);
        root.refresh();
    }
    onScrollDown: {
        Exec.run(["wpctl", "set-volume", "@DEFAULT_AUDIO_SINK@", "0.05-", "-l", "1.0"]);
        root.refresh();
    }
}
