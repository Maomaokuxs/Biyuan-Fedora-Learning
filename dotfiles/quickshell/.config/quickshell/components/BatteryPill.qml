import QtQuick
import Quickshell.Services.UPower

// 原生电池模块：替代 scripts/battery.sh。
// 语义一致：无电池 → 隐藏；Charging/FullyCharged → 󱐋；否则按 90/70/40/15 分档。
Pill {
    id: root
    property var dev: UPower.displayDevice

    pillText: {
        var d = root.dev;
        if (!d || !d.ready || !d.isPresent)
            return "";
        var p = d.percentage;
        var cap = Math.round(p <= 1 ? p * 100 : p);
        var st = d.state;
        if (st === UPowerDeviceState.Charging || st === UPowerDeviceState.FullyCharged || st === UPowerDeviceState.PendingCharge)
            return Icons.batCharging + " " + cap + "%";
        var icon = cap >= 90 ? Icons.bat4 : cap >= 70 ? Icons.bat3 : cap >= 40 ? Icons.bat2 : cap >= 15 ? Icons.bat1 : Icons.bat0;
        return icon + " " + cap + "%";
    }
}
