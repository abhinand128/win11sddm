/**
 * win11SDDM - Clock Component
 * Author: abhinand128
 */
import QtQuick

Item {
    id: clock
    width: timeText.width
    height: timeText.height

    property string backgroundSource: ""
    property string fontFamily: "sans-serif"
    property color textColor: "white"
    property string timeStr: ""

    function updateTime() {
        var date = new Date();
        var hours = date.getHours();
        var minutes = date.getMinutes();

        if (config.use24HourClock !== "true") {
            hours = hours % 12;
            if (hours === 0) hours = 12;
        }

        var hStr = hours < 10 ? "" + hours : "" + hours; // Windows 11 doesn't always show leading zero for hours
        var mStr = minutes < 10 ? "0" + minutes : "" + minutes;

        clock.timeStr = hStr + ":" + mStr;
    }

    Component.onCompleted: {
        updateTime();
    }

    Text {
        id: timeText
        anchors.centerIn: parent
        text: clock.timeStr
        color: clock.textColor
        font.pixelSize: 120
        font.family: clock.fontFamily
        font.weight: Font.DemiBold
        antialiasing: true
    }

    Timer {
        interval: 1000
        running: true
        repeat: true
        onTriggered: updateTime()
    }
}
