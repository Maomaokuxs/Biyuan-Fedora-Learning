pragma Singleton

import QtQuick
import Quickshell

// 进程发射器：替代散落的 Qt.createQmlObject(Process{...})。
// 后者每次点击新建永久 QML 对象不销毁，越点越漏；execDetached 无此问题。
QtObject {
    function sh(cmd: string) {
        Quickshell.execDetached(["bash", "-c", cmd]);
    }
    function run(args) {
        Quickshell.execDetached(args);
    }
}
