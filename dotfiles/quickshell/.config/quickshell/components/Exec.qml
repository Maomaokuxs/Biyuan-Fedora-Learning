pragma Singleton

import QtQuick
import Quickshell

// 进程发射器：替代散落的 Qt.createQmlObject(Process{...})。
// 后者每次点击新建永久 QML 对象不销毁，越点越漏；execDetached 无此问题。
QtObject {
    // 可移植基址：跟随 quickshell 配置目录（-p 指定哪就是哪），
    // 全仓脚本引用一律经此拼接，禁止写死 $HOME/Documents 等个人路径。
    property string scriptDir: Quickshell.configDir + "/scripts"
    property string commonDir: scriptDir + "/common"
    function sh(cmd: string) {
        Quickshell.execDetached(["bash", "-c", cmd]);
    }
    function run(args) {
        Quickshell.execDetached(args);
    }
}
