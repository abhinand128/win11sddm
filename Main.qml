/**
 * win11sddm
 * Author: abhinand128
 * GitHub: https://github.com/abhinand128/win11sddm.git
 */
import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import "components"

Rectangle {
    id: container
    width: 1920
    height: 1080
    color: config.backgroundColor
    focus: !loginState.visible

    // User & Session Logic (Root Level)
    property int userIndex: 0
    property int sessionIndex: 0
    property bool isLoggingIn: false

    property var backgroundImages: ["assets/background1.jpg", "assets/background2.jpg","assets/background3.jpg","assets/background4.jpg","assets/background5.jpg","assets/background6.jpg","assets/background7.jpg",
            "assets/background8.jpg","assets/background9.jpg","assets/background10.jpg","assets/background11.jpg","assets/background12.jpg","assets/background13.jpg","assets/background14.jpg"]

    Component.onCompleted: {
        if (typeof userModel !== "undefined" && userModel.lastIndex >= 0) userIndex = userModel.lastIndex;
        if (typeof sessionModel !== "undefined" && sessionModel.lastIndex >= 0) sessionIndex = sessionModel.lastIndex;
        if (config.forceVirtualKeyboard !== "true") Qt.inputMethod.hide();
        backgroundImage.source = backgroundImages[Math.floor(Math.random() * backgroundImages.length)];
    }

    function cleanName(name) {
        if (!name) return "";
        var s = name.toString();
        if (s.endsWith("/")) s = s.substring(0, s.length - 1);
        if (s.indexOf("/") !== -1) s = s.substring(s.lastIndexOf("/") + 1);
        if (s.indexOf(".desktop") !== -1) s = s.substring(0, s.indexOf(".desktop"));
        s = s.replace(/[-_]/g, ' ');
        return s.charAt(0).toUpperCase() + s.slice(1);
    }

    function doLogin() {
        if (!loginState.visible || isLoggingIn) return;

        var user = "";
        if (typeof userModel !== "undefined" && userModel.count > 0) {
            var idx = container.userIndex;
            if (idx < 0 || idx >= userModel.count) idx = 0;

            var edit = userModel.data(userModel.index(idx, 0), Qt.EditRole);
            var nameRole = userModel.data(userModel.index(idx, 0), Qt.UserRole + 1);
            var display = userModel.data(userModel.index(idx, 0), Qt.DisplayRole);

            user = edit ? edit.toString() : (nameRole ? nameRole.toString() : (display ? display.toString() : ""));
        }

        if (!user || user === "" || user === "User") {
            user = sddm.lastUser;
        }

        if (!user && typeof userModel !== "undefined" && userModel.count > 0) {
            var firstEdit = userModel.data(userModel.index(0, 0), Qt.EditRole);
            user = firstEdit ? firstEdit.toString() : "";
        }

        if (!user) return;

        container.isLoggingIn = true;
        var pass = passwordField.text;
        var sess = container.sessionIndex;

        if (typeof sessionModel !== "undefined") {
            if (sess < 0 || sess >= sessionModel.count) sess = 0;
        } else {
            sess = 0;
        }

        console.log("Pixie SDDM: Attempting login for user [" + user + "] session index [" + sess + "]");
        sddm.login(user.trim(), pass, sess);
        loginTimeout.start();
    }

    Timer {
        id: loginTimeout
        interval: 5000
        onTriggered: container.isLoggingIn = false
    }

    Timer {
        id: hideKeyboardTimer
        interval: 100
        onTriggered: if (config.forceVirtualKeyboard !== "true") Qt.inputMethod.hide();
    }

    Connections {
        target: sddm
        function onLoginFailed() {
            container.isLoggingIn = false
            loginTimeout.stop()
            loginState.isError = true
            shakeAnimation.start()
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            loginTimeout.stop()
        }
    }

    // Dynamic Color Configuration
    property color extractedAccent: config.accentColor
    property color baseColor: config.backgroundColor
    property color surfaceColor: Qt.rgba(1, 1, 1, 0.1) // Glassmorphism
    property color surfaceVariantColor: Qt.rgba(1, 1, 1, 0.15)
    property bool uiReady: config.autoColor !== "true" || colorExtractor.processed

    Timer {
        id: colorDelay
        interval: 1000 // Give it a full second
        repeat: true   // Keep trying until we succeed
        running: backgroundImage.status === Image.Ready && !colorExtractor.processed && config.autoColor === "true"
        onTriggered: colorExtractor.requestPaint()
    }

    Canvas {
        id: colorExtractor
        width: 60; height: 60
        x: -100; y: -100 // Off-screen but "visible" for reliable rendering
        z: -1
        renderTarget: Canvas.Image
        property bool processed: false
        property int retries: 0 // Add this to track GPU sync delays

        onPaint: {
            var ctx = getContext("2d");
            var res = 60;
            ctx.clearRect(0, 0, res, res);
            ctx.drawImage(backgroundImage, 0, 0, res, res);
            var imgData = ctx.getImageData(0, 0, res, res).data;

            if (!imgData || imgData.length === 0) return;

            // 36 Buckets (10 degrees each) for high resolution hue detection
            var histogram = new Array(36).fill(0);
            var sampleColors = new Array(36).fill(null);
            var vibrantFound = false;

            // FIX: Check if canvas read pure black (GPU sync delay bug)
            var pixelSum = 0;
            for (var p = 0; p < imgData.length; p++) pixelSum += imgData[p];

            if (pixelSum === 0) {
                retries++;
                if (retries > 3) {
                    // If it's still pure black after 3 tries, it's a true black wallpaper
                    container.extractedAccent = "#D0D0D0";
                    console.log("Pixie SDDM: Pure black wallpaper detected. Using neutral contrast.");
                    processed = true;
                }
                return; // Keep trying if it's just a GPU delay
            }

            // Reset retries if we got pixels
            retries = 0;

            for (var i = 0; i < imgData.length; i += 4) {
                var r = imgData[i] / 255;
                var g = imgData[i+1] / 255;
                var b = imgData[i+2] / 255;
                var pCol = Qt.rgba(r, g, b, 1.0);

                // Filter: Must be colorful and not too dark
                if (pCol.hsvSaturation > 0.3 && pCol.hsvValue > 0.15) {
                    var h = pCol.hsvHue * 360;
                    if (h < 0) continue;

                    var bIdx = Math.floor(h / 10) % 36;
                    var weight = pCol.hsvSaturation * pCol.hsvValue;
                    histogram[bIdx] += weight;

                    if (!sampleColors[bIdx] || weight > (sampleColors[bIdx].hsvSaturation * sampleColors[bIdx].hsvValue)) {
                        sampleColors[bIdx] = pCol;
                    }
                    vibrantFound = true;
                }
            }

            if (!vibrantFound) {
                // Calculate average brightness for monochrome wallpapers (greys/whites)
                var totalBrightness = 0;
                var pixelCount = imgData.length / 4;
                for (var k = 0; k < imgData.length; k += 4) {
                    var r_l = imgData[k] / 255;
                    var g_l = imgData[k+1] / 255;
                    var b_l = imgData[k+2] / 255;
                    totalBrightness += (0.299 * r_l + 0.587 * g_l + 0.114 * b_l);
                }
                var avgBrightness = totalBrightness / pixelCount;

                container.extractedAccent = avgBrightness < 0.5 ? "#D0D0D0" : "#404040";
                console.log("Pixie SDDM: No vibrant colors. Avg brightness: " + avgBrightness.toFixed(2) + ". Using neutral contrast.");
                processed = true;
                return;
            }

            // Merge Red wrap (350-360 and 0-10)
            histogram[0] += histogram[35];

            // Find the most frequent vibrant hue (The Mode)
            var maxCount = -1;
            var winnerIdx = -1;
            for (var j = 0; j < 35; j++) {
                if (histogram[j] > maxCount) {
                    maxCount = histogram[j];
                    winnerIdx = j;
                }
            }

            if (winnerIdx !== -1 && sampleColors[winnerIdx]) {
                var finalColor = sampleColors[winnerIdx];
                var h = finalColor.hsvHue;
                var s = Math.max(0.35, Math.min(0.55, finalColor.hsvSaturation * 0.9));
                container.extractedAccent = Qt.hsva(h, s, 0.95, 1.0);
                console.log("Pixie SDDM: SUCCESS! Extracted Hue: " + (h * 360).toFixed(0) + "°");
                processed = true;
            }
        }
    }

    Connections {
        target: backgroundImage
        function onStatusChanged() {
            if (backgroundImage.status === Image.Ready) {
                colorExtractor.processed = false;
                colorDelay.start();
            }
        }
    }

    FontLoader { id: fontRegular; source: "assets/fonts/FlexRounded-R.ttf" }
    FontLoader { id: fontMedium; source: "assets/fonts/FlexRounded-M.ttf" }
    FontLoader { id: fontBold; source: "assets/fonts/FlexRounded-B.ttf" }

    Image {
        id: backgroundImage
        source: config.background
        anchors.fill: parent
        fillMode: Image.PreserveAspectCrop
    }

    // High-Quality Standalone Blur (Qt6 Native)
    MultiEffect {
        id: backgroundBlur
        anchors.fill: parent
        source: backgroundImage
        blurEnabled: true
        blurMax: 64
        blur: loginState.visible ? 1.0 : 0.0
        opacity: loginState.visible ? 1.0 : 0.0
        autoPaddingEnabled: false

        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        Behavior on blur { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: loginState.visible ? 0.3 : 0.1
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    PowerBar {
        anchors {
            bottom: parent.bottom
            right: parent.right
            bottomMargin: 30
            rightMargin: 40
        }
        textColor: "white"
        z: 100
        opacity: container.uiReady ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 300 } }
    }

    Shortcut {
        sequence: "Escape"
        enabled: loginState.visible
        onActivated: {
            loginState.visible = false;
            loginState.isError = false;
            passwordField.text = "";
            container.focus = true;
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: loginState.visible
        onActivated: container.doLogin()
    }


    Item {
        id: lockState
        anchors.fill: parent
        visible: !loginState.visible
        opacity: visible ? 1 : 0
        Behavior on opacity { NumberAnimation { duration: 400 } }

        Column {
            anchors.top: parent.top
            anchors.topMargin: 120
            anchors.horizontalCenter: parent.horizontalCenter
            spacing: 0
            
            Clock {
                id: mainClock
                anchors.horizontalCenter: parent.horizontalCenter
                fontFamily: config.fontFamily
                textColor: "white"
            }

            Text {
                id: dateText
                text: Qt.formatDateTime(new Date(), "dddd, MMMM d")
                color: "white"
                font.pixelSize: 32
                font.family: config.fontFamily
                font.weight: Font.Light
                anchors.horizontalCenter: parent.horizontalCenter
                opacity: container.uiReady ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }
            }
        }

        Text {
            text: "Press any key to unlock"
            color: "white"
            font.pixelSize: 18
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin: 100
            }
            opacity: 0.7
        }

        MouseArea {
            anchors.fill: parent
            onClicked: {
                loginState.visible = true;
                passwordField.forceActiveFocus();
            }
        }
    }

    Item {
        id: loginState
        anchors.fill: parent
        visible: false
        opacity: visible ? 1 : 0
        z: 10
        Behavior on opacity { NumberAnimation { duration: 400 } }

        onVisibleChanged: {
            if (visible) {
                passwordField.forceActiveFocus();
                if (config.forceVirtualKeyboard !== "true") Qt.inputMethod.hide();
            }
        }

        property bool isError: false
        SequentialAnimation {
            id: shakeAnimation
            loops: 2
            PropertyAnimation { target: loginContent; property: "x"; from: (container.width - loginContent.width)/2; to: (container.width - loginContent.width)/2 - 10; duration: 50; easing.type: Easing.InOutQuad }
            PropertyAnimation { target: loginContent; property: "x"; from: (container.width - loginContent.width)/2 - 10; to: (container.width - loginContent.width)/2 + 10; duration: 50; easing.type: Easing.InOutQuad }
            PropertyAnimation { target: loginContent; property: "x"; from: (container.width - loginContent.width)/2 + 10; to: (container.width - loginContent.width)/2; duration: 50; easing.type: Easing.InOutQuad }
            onStopped: isError = false
        }

        ColumnLayout {
            id: loginContent
            width: 320
            anchors.centerIn: parent
            spacing: 20

            Item {
                Layout.preferredWidth: 160
                Layout.preferredHeight: 160
                Layout.alignment: Qt.AlignHCenter

                Rectangle {
                    id: avatarFallback
                    anchors.fill: parent
                    color: surfaceColor
                    radius: width / 2
                    visible: avatar.status !== Image.Ready
                    border.color: "white"
                    border.width: 1

                    Text {
                        anchors.centerIn: parent
                        text: {
                            var n = "";
                            if (typeof userModel !== "undefined" && userModel.count > 0) {
                                var d = userModel.data(userModel.index(container.userIndex, 0), Qt.DisplayRole);
                                var nr = userModel.data(userModel.index(container.userIndex, 0), Qt.UserRole + 1);
                                n = d ? d.toString() : (nr ? nr.toString() : "U");
                            } else {
                                n = sddm.lastUser ? sddm.lastUser : "U";
                            }
                            return n.charAt(0).toUpperCase();
                        }
                        color: "white"
                        font.pixelSize: 64
                        font.family: config.fontFamily
                    }
                }

                Canvas {
                    id: avatarCanvas
                    anchors.fill: parent
                    visible: avatar.status === Image.Ready

                    onPaint: {
                        var ctx = getContext("2d");
                        ctx.reset();
                        ctx.beginPath();
                        ctx.arc(width/2, height/2, width/2, 0, 2 * Math.PI);
                        ctx.closePath();
                        ctx.clip();
                        ctx.drawImage(avatar, 0, 0, width, height);
                    }

                    Timer {
                        id: repaintTimer
                        interval: 500
                        onTriggered: avatarCanvas.requestPaint()
                    }

                    Image {
                        id: avatar
                        anchors.fill: parent
                        fillMode: Image.PreserveAspectCrop
                        smooth: true
                        visible: false

                        Component.onCompleted: {
                            var s = Qt.resolvedUrl("assets/face.icon");
                            if (typeof userModel !== "undefined" && userModel.count > 0) {
                                var icon = userModel.data(userModel.index(container.userIndex, 0), Qt.UserRole + 3);
                                if (icon && icon.toString().match(/\.(jpg|jpeg|png|bmp|webp|svg)$/i)) {
                                    s = icon.toString();
                                }
                            }
                            source = s;
                        }

                        onStatusChanged: {
                            if (status === Image.Ready) {
                                repaintTimer.start();
                            }
                        }
                    }
                }
            }

            Text {
                id: userNameLabel
                Layout.alignment: Qt.AlignHCenter
                text: {
                    if (typeof userModel !== "undefined" && userModel.count > 0) {
                        var idx = container.userIndex;
                        var modelIdx = userModel.index(idx, 0);
                        var display = userModel.data(modelIdx, Qt.DisplayRole);
                        var edit = userModel.data(modelIdx, Qt.EditRole);
                        var nr = userModel.data(modelIdx, Qt.UserRole + 1);
                        var realName = userModel.data(modelIdx, Qt.UserRole + 2);
                        var finalName = display ? display.toString() : (realName ? realName.toString() : (nr ? nr.toString() : (edit ? edit.toString() : "User")));
                        return cleanName(finalName);
                    }
                    return cleanName(sddm.lastUser ? sddm.lastUser : "User");
                }
                color: "white"
                font.pixelSize: 36
                font.weight: Font.DemiBold
                font.family: config.fontFamily
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 40
                Layout.topMargin: 10

                TextField {
                    id: passwordField
                    anchors.fill: parent
                    echoMode: TextInput.Password
                    horizontalAlignment: Text.AlignLeft
                    leftPadding: 15
                    rightPadding: 45
                    font.pixelSize: 16
                    color: "white"
                    focus: loginState.visible
                    enabled: !container.isLoggingIn
                    inputMethodHints: Qt.ImhNoPredictiveText | Qt.ImhSensitiveData

                    onActiveFocusChanged: {
                        if (activeFocus && config.forceVirtualKeyboard !== "true") {
                            Qt.inputMethod.hide();
                            hideKeyboardTimer.start();
                        }
                    }

                    background: Rectangle {
                        color: Qt.rgba(0, 0, 0, 0.3)
                        radius: 4
                        border.width: parent.activeFocus ? 2 : 1
                        border.color: parent.activeFocus ? "#0067c0" : Qt.rgba(1, 1, 1, 0.3)
                    }

                    Text {
                        text: "Password"
                        color: "white"
                        font.pixelSize: 16
                        visible: !parent.text
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 15
                        opacity: 0.5
                    }

                    onAccepted: container.doLogin()

                    RoundButton {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 5
                        width: 30
                        height: 30
                        flat: true
                        onClicked: container.doLogin()
                        
                        contentItem: Text {
                            text: "→"
                            color: "white"
                            font.pixelSize: 20
                            horizontalAlignment: Text.AlignHCenter
                            verticalAlignment: Text.AlignVCenter
                        }
                        background: Rectangle {
                            color: parent.pressed ? Qt.rgba(1, 1, 1, 0.2) : "transparent"
                            radius: 4
                        }
                    }
                }
            }

            Row {
                Layout.alignment: Qt.AlignHCenter
                spacing: 20
                visible: (typeof userModel !== "undefined" && userModel.count > 1) || (typeof sessionModel !== "undefined" && sessionModel.count > 1)

                Text {
                    text: "Sign-in options"
                    color: "white"
                    font.pixelSize: 14
                    opacity: 0.8
                    font.family: config.fontFamily
                    
                    MouseArea {
                        anchors.fill: parent
                        onClicked: userPopup.open()
                    }
                }
            }

            Text {
                id: numLockIndicator
                text: "Num Lock is on"
                color: "white"
                font.pixelSize: 12
                Layout.alignment: Qt.AlignHCenter
                visible: {
                    if (typeof keyboard !== "undefined" && typeof keyboard.numLock !== "undefined") return keyboard.numLock;
                    return false;
                }
                opacity: 0.7
            }
        }

        // Session indicator in bottom left
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 30
            width: sessionLabel.width + 80
            height: 40
            color: sessionClickArea.pressed ? Qt.rgba(1, 1, 1, 0.2) : Qt.rgba(1, 1, 1, 0.1)
            radius: 4
            border.color: Qt.rgba(1, 1, 1, 0.2)
            border.width: 1

            RowLayout {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    text: "󰟀"
                    color: "white"
                    font.pixelSize: 16
                }
                Text {
                    id: sessionLabel
                    text: {
                        if (typeof sessionModel !== "undefined" && sessionModel.count > 0) {
                            var idx = container.sessionIndex;
                            var modelIdx = sessionModel.index(idx, 0);
                            var n = sessionModel.data(modelIdx, Qt.UserRole + 4);
                            var f = sessionModel.data(modelIdx, Qt.UserRole + 2);
                            var d = sessionModel.data(modelIdx, Qt.DisplayRole);
                            var finalName = n ? n.toString() : (f ? f.toString() : (d ? d.toString() : "Session " + (idx + 1)));
                            return cleanName(finalName);
                        }
                        return "Hyprland";
                    }
                    color: "white"
                    font.pixelSize: 14
                }
            }

            MouseArea {
                id: sessionClickArea
                anchors.fill: parent
                onClicked: sessionPopup.open()
            }
        }
    }

    Keys.onPressed: function(event) {
        if (!loginState.visible) {
            loginState.visible = true;
            passwordField.forceActiveFocus();
            event.accepted = true;
        }
    }

    Popup {
        id: userPopup
        width: 260
        height: (typeof userModel !== "undefined") ? Math.min(300, userModel.count * 50 + 20) : 100
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2 - 50
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: userList.forceActiveFocus()
        background: Rectangle {
            color: Qt.rgba(0.1, 0.1, 0.1, 0.9)
            radius: 8
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 } }
        ListView {
            id: userList
            anchors.fill: parent
            anchors.margins: 10
            model: (typeof userModel !== "undefined") ? userModel : null
            spacing: 5
            clip: true
            focus: true
            currentIndex: container.userIndex
            highlightFollowsCurrentItem: true
            delegate: ItemDelegate {
                width: parent.width
                height: 40
                property bool isCurrent: index === userList.currentIndex
                background: Rectangle {
                    color: isCurrent ? Qt.rgba(1, 1, 1, 0.1) : (hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    radius: 4
                }
                contentItem: RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    Item { Layout.preferredWidth: 4 }
                    Rectangle {
                        Layout.preferredWidth: 28
                        Layout.preferredHeight: 28
                        Layout.alignment: Qt.AlignVCenter
                        color: isCurrent ? "white" : Qt.rgba(1, 1, 1, 0.2)
                        radius: 14
                        Text {
                            anchors.centerIn: parent
                            text: {
                                var mIdx = userModel.index(index, 0);
                                var d = userModel.data(mIdx, Qt.DisplayRole);
                                var n_r = userModel.data(mIdx, Qt.UserRole + 1);
                                var finalVal = d ? d.toString() : (n_r ? n_r.toString() : "U");
                                return finalVal.charAt(0).toUpperCase();
                            }
                            color: isCurrent ? "black" : "white"
                            font.pixelSize: 12
                            font.weight: Font.Bold
                        }
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            var mIdx = userModel.index(index, 0);
                            var d = userModel.data(mIdx, Qt.DisplayRole);
                            var n_r = userModel.data(mIdx, Qt.UserRole + 1);
                            var r = userModel.data(mIdx, Qt.UserRole + 2);
                            var e = userModel.data(mIdx, Qt.EditRole);
                            return cleanName(d ? d : (r ? r : (n_r ? n_r : e)));
                        }
                        color: "white"
                        font.pixelSize: 14
                        font.family: config.fontFamily
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
                onClicked: {
                    container.userIndex = index;
                    userPopup.close();
                }
            }
            Keys.onDownPressed: incrementCurrentIndex()
            Keys.onUpPressed: decrementCurrentIndex()
            Keys.onReturnPressed: { container.userIndex = currentIndex; userPopup.close(); }
            Keys.onEnterPressed: { container.userIndex = currentIndex; userPopup.close(); }
        }
    }

    Popup {
        id: sessionPopup
        width: 260
        height: (typeof sessionModel !== "undefined") ? Math.min(250, sessionModel.count * 50 + 20) : 100
        x: (parent.width - width) / 2
        y: (parent.height - height) / 2 + 80
        modal: true
        focus: true
        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutside
        onOpened: sessionList.forceActiveFocus()
        background: Rectangle {
            color: Qt.rgba(0.1, 0.1, 0.1, 0.9)
            radius: 8
            border.color: Qt.rgba(1, 1, 1, 0.1)
            border.width: 1
        }
        enter: Transition { NumberAnimation { property: "opacity"; from: 0; to: 1; duration: 200 } }
        exit: Transition { NumberAnimation { property: "opacity"; from: 1; to: 0; duration: 200 } }
        ListView {
            id: sessionList
            anchors.fill: parent
            anchors.margins: 10
            model: (typeof sessionModel !== "undefined") ? sessionModel : null
            spacing: 5
            clip: true
            focus: true
            currentIndex: container.sessionIndex
            highlightFollowsCurrentItem: true
            delegate: ItemDelegate {
                width: parent.width
                height: 40
                property bool isCurrent: index === sessionList.currentIndex
                background: Rectangle {
                    color: isCurrent ? Qt.rgba(1, 1, 1, 0.1) : (hovered ? Qt.rgba(1, 1, 1, 0.05) : "transparent")
                    radius: 4
                }
                contentItem: RowLayout {
                    anchors.fill: parent
                    spacing: 12
                    Item { Layout.preferredWidth: 4 }
                    Text {
                        Layout.preferredWidth: 20
                        text: "󰟀"
                        color: isCurrent ? "white" : "gray"
                        font.pixelSize: 16
                        horizontalAlignment: Text.AlignHCenter
                        verticalAlignment: Text.AlignVCenter
                    }
                    Text {
                        Layout.fillWidth: true
                        text: {
                            var n_val = sessionModel.data(sessionModel.index(index, 0), Qt.UserRole + 4);
                            var f_val = sessionModel.data(sessionModel.index(index, 0), Qt.UserRole + 2);
                            return cleanName(n_val ? n_val : f_val);
                        }
                        color: "white"
                        font.pixelSize: 14
                        font.family: config.fontFamily
                        verticalAlignment: Text.AlignVCenter
                        elide: Text.ElideRight
                    }
                }
                onClicked: {
                    container.sessionIndex = index;
                    sessionPopup.close();
                }
            }
            Keys.onDownPressed: incrementCurrentIndex()
            Keys.onUpPressed: decrementCurrentIndex()
            Keys.onReturnPressed: { container.sessionIndex = currentIndex; sessionPopup.close(); }
            Keys.onEnterPressed: { container.sessionIndex = currentIndex; sessionPopup.close(); }
        }
    }
}
