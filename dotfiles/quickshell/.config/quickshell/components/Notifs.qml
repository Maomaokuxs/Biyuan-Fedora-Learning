pragma Singleton

import QtQuick
import Quickshell.Services.Notifications

// 通知中心数据层：接管 org.freedesktop.Notifications（mako/dunst必须退其一），
// tracked 实时列表驱动 toast，closed 的快照进 history（cap 50）。
// 注：用 Item 而非 QtObject，因需容纳 NotificationServer/Instantiator 子对象。
Item {
    id: root
    visible: false

    property var server: NotificationServer {
        id: server
        // 关键：收到的通知默认丢弃，必须显式标记 tracked 才会进列表
        //（这就是之前一直 0/0 的原因，不是 bug，是 opt-in 设计）。
        // 计数也放这里：信号必达，比 Instantiator delegate 可靠。
        // kwrited（wall 广播转通知，应用名显示“本地系统消息服务”）直接丢弃，
        // 与 mako 时代 [summary="本地系统消息服务"] invisible=1 同逻辑。
        onNotification: n => {
            var hints = {};
            try { hints = n.hints || {}; } catch (e) {}
            var de = "";
            try { de = n.desktopEntry || ""; } catch (e) {}
            if (de === "org.kde.kded6" || hints["x-kde-appname"] === "kwrited") {
                console.log("notification-center: kwrited wall 广播已静默丢弃");
                return;
            }
            n.tracked = true;
            root.unread++;
        }
    }
    property var history: []
    property int unread: 0

    function pushHistory(n) {
        var entry = {
            app: n.appName || "",
            summary: n.summary || "",
            body: n.body || "",
            time: new Date()
        };
        root.history = [entry].concat(root.history).slice(0, 50);
    }
    function markRead() {
        root.unread = 0;
    }
    function clearHistory() {
        root.history = [];
        root.unread = 0;
    }

    // 关闭时快照进历史
    Instantiator {
        model: server.trackedNotifications.values
        delegate: Connections {
            required property var modelData
            target: modelData
            function onClosed() {
                root.pushHistory(modelData);
            }
        }
    }
}
