import QtQuick
import Quickshell.Bluetooth

// 原生蓝牙模块：替代 scripts/bluetooth.sh。
// 语义一致：forceHidden（systemHidden 开关）→ 折叠；适配器开启 → ，否则 󰂲。
// 左键 kcmshell6，右键 rfkill toggle。
Pill {
    id: root

    function adapter() {
        var a = Bluetooth.adapters.values;
        return a.length > 0 ? a[0] : null;
    }

    pillText: {
        var a = root.adapter();
        if (!a)
            return Icons.btOff;
        return a.enabled ? Icons.btOn : Icons.btOff;
    }

    clickLeft: "kcmshell6 kcm_bluetooth"
    clickRight: "rfkill toggle bluetooth"
}
