pragma Singleton

import QtQuick

// 全局图标源：码点全部取自 waybar 原配置/脚本实测值（见 docs 注释），
// 新增图标先过 fc-list ":charset=XXXX" 再登记，禁止手打字形。
QtObject {
    readonly property string launcher: "\u{F08DB}"
    readonly property string power: "\u23FB"
    readonly property string musicPlaying: "\u{F0386}"
    readonly property string musicPaused: "\u{F03E4}"
    readonly property string prev: "\uF048"
    readonly property string play: "\uF04B"
    readonly property string pause: "\uF04C"
    readonly property string next: "\uF051"
    readonly property string shuffle: "\u{F049D}"
    readonly property string loopOff: "\uF455"
    readonly property string loopAll: "\uF454"
    readonly property string loopOne: "\uF456"
    readonly property string wallpaper: "\uF03E"
    readonly property string bell: "\uF0F3"
    readonly property string coverFallback: "\uF001"
    readonly property string volMute: "\u{F075F}"
    readonly property string vol0: "\uF026"
    readonly property string volLow: "\uF027"
    readonly property string volHigh: "\uF028"
    readonly property string briLow: "\u{F00DE}"
    readonly property string briMid: "\u{F00DF}"
    readonly property string briHigh: "\u{F00E0}"
    readonly property string cpu: "\uF4BC"
    readonly property string mem: "\uEFC5"
    readonly property string net: "\u{F0928}"
    readonly property string btOn: "\uF293"
    readonly property string btOff: "\u{F00B2}"
    readonly property string bat0: "\uF244"
    readonly property string bat1: "\uF243"
    readonly property string bat2: "\uF242"
    readonly property string bat3: "\uF241"
    readonly property string bat4: "\uF240"
    readonly property string batCharging: "\u{F140B}"
}
