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
    focus: lockScreenActive

    // User & Session Logic (Root Level)
    property int userIndex: 0
    property int sessionIndex: 0
    property bool isLoggingIn: false

    // Add new background images here: just drop the file in assets/ and add the path below
    property var backgroundImages: [
        "assets/background1.jpg",  "assets/background2.jpg",  "assets/background3.jpg",
        "assets/background4.jpg",  "assets/background5.jpg",
        "assets/background7.jpg",  "assets/background8.jpg",
        "assets/background13.jpg", "assets/background14.jpg",
        "assets/background16.jpg", "assets/background17.jpg", "assets/background18.jpg",
        "assets/background19.jpg",
        "assets/background22.jpg", "assets/background24.jpg",
        "assets/background26.jpg"
    ]

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

        // Show loading overlay with spinning dots
        loginLoadingOverlay.show();

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
            loginLoadingOverlay.hide()
            loginState.isError = true
            shakeAnimation.start()
            passwordField.text = ""
            passwordField.forceActiveFocus()
        }
        function onLoginSucceeded() {
            loginTimeout.stop()
            // Loading overlay stays visible — it will naturally disappear
            // when SDDM kills the greeter as the desktop takes over
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
        blur: !container.lockScreenActive ? 1.0 : 0.0
        opacity: !container.lockScreenActive ? 1.0 : 0.0
        autoPaddingEnabled: false

        Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
        Behavior on blur { NumberAnimation { duration: 600; easing.type: Easing.InOutQuad } }
    }

    Rectangle {
        anchors.fill: parent
        color: "black"
        opacity: !container.lockScreenActive ? 0.3 : 0.1
        Behavior on opacity { NumberAnimation { duration: 400 } }
    }

    // Simple fade from black on startup
    Rectangle {
        id: startupFade
        anchors.fill: parent
        color: "black"
        opacity: 1.0
        z: 999

        Timer {
            id: startupFadeTimer
            interval: 300
            running: true
            onTriggered: startupFadeAnim.start()
        }

        NumberAnimation {
            id: startupFadeAnim
            target: startupFade
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: 1200
            easing.type: Easing.OutQuad
            onFinished: startupFade.visible = false
        }
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
        enabled: loginState.visible && !container.lockScreenAnimating
        onActivated: {
            container.returnToLockScreen();
        }
    }

    Shortcut {
        sequences: ["Return", "Enter"]
        enabled: loginState.visible
        onActivated: container.doLogin()
    }


    // Lock screen state tracking
    property bool lockScreenActive: true
    property bool lockScreenAnimating: false

    Item {
        id: lockState
        anchors.fill: parent
        visible: true
        opacity: 1.0
        z: 5

        // Clock container with explicit positioning for animation
        Item {
            id: clockContainer
            anchors.horizontalCenter: parent.horizontalCenter
            width: clockColumn.width
            height: clockColumn.height
            y: parent.height * 0.15  // Resting position

            // Start off-screen below for entrance animation
            Component.onCompleted: {
                clockContainer.y = parent.height * 0.6;
                clockContainer.opacity = 0.0;
            }

            Column {
                id: clockColumn
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
                }
            }
        }

        // "Press any key" hint
        Text {
            id: hintText
            text: "Press any key to unlock"
            color: "white"
            font.pixelSize: 18
            anchors {
                bottom: parent.bottom
                horizontalCenter: parent.horizontalCenter
                bottomMargin: 100
            }
            opacity: 0.0  // Start invisible, entrance animation will show it
        }

        MouseArea {
            anchors.fill: parent
            enabled: container.lockScreenActive && !container.lockScreenAnimating
            onClicked: {
                container.transitionToLogin();
            }
        }
    }

    // --- Entrance Animation (clock slides up into position on startup) ---
    ParallelAnimation {
        id: clockEntranceAnim

        NumberAnimation {
            target: clockContainer
            property: "y"
            from: container.height * 0.6
            to: container.height * 0.15
            duration: 300
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: clockContainer
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 400
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: hintText
            property: "opacity"
            from: 0.0
            to: 0.7
            duration: 300
            easing.type: Easing.OutQuad
        }
    }

    // Trigger entrance after startup fade begins clearing
    Timer {
        id: entranceAnimTimer
        interval: 800
        running: true
        onTriggered: clockEntranceAnim.start()
    }

    // --- Exit Animation (clock slides up & fades out when key pressed, like Win11) ---
    ParallelAnimation {
        id: clockExitAnim

        NumberAnimation {
            target: clockContainer
            property: "y"
            to: -clockContainer.height - 50  // Slide above the screen
            duration: 300
            easing.type: Easing.InOutCubic
        }
        NumberAnimation {
            target: clockContainer
            property: "opacity"
            to: 0.0
            duration: 400
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: hintText
            property: "opacity"
            to: 0.0
            duration: 450
            easing.type: Easing.InQuad
        }
        NumberAnimation {
            target: lockState
            property: "opacity"
            to: 0.0
            duration: 600
            easing.type: Easing.InOutQuad
        }

        onFinished: {
            lockState.visible = false;
            loginState.visible = true;
            loginState.opacity = 0.0;
            loginFadeInAnim.start();
            passwordField.forceActiveFocus();
            container.lockScreenAnimating = false;
        }
    }

    // --- Login form fade-in after clock exits ---
    NumberAnimation {
        id: loginFadeInAnim
        target: loginState
        property: "opacity"
        from: 0.0
        to: 1.0
        duration: 500
        easing.type: Easing.OutQuad
    }

    // --- Reverse animation: login fades out, clock slides back in (Escape) ---
    ParallelAnimation {
        id: clockReturnAnim

        NumberAnimation {
            target: clockContainer
            property: "y"
            to: container.height * 0.15
            duration: 450
            easing.type: Easing.OutCubic
        }
        NumberAnimation {
            target: clockContainer
            property: "opacity"
            to: 1.0
            duration: 600
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: hintText
            property: "opacity"
            to: 0.7
            duration: 450
            easing.type: Easing.OutQuad
        }
        NumberAnimation {
            target: lockState
            property: "opacity"
            to: 1.0
            duration: 500
            easing.type: Easing.OutQuad
        }

        onFinished: {
            container.lockScreenAnimating = false;
        }
    }

    NumberAnimation {
        id: loginFadeOutAnim
        target: loginState
        property: "opacity"
        from: 1.0
        to: 0.0
        duration: 200
        easing.type: Easing.InQuad
        onFinished: {
            loginState.visible = false;
            lockState.visible = true;
            clockReturnAnim.start();
        }
    }

    // Central function to transition to login
    function transitionToLogin() {
        if (!container.lockScreenActive || container.lockScreenAnimating) return;
        container.lockScreenActive = false;
        container.lockScreenAnimating = true;
        clockExitAnim.start();
    }

    // Central function to return to lock screen
    function returnToLockScreen() {
        if (container.lockScreenActive || container.lockScreenAnimating) return;
        container.lockScreenActive = true;
        container.lockScreenAnimating = true;
        passwordField.text = "";
        loginState.isError = false;
        loginFadeOutAnim.start();
        container.focus = true;
    }

    Item {
        id: loginState
        anchors.fill: parent
        visible: false
        opacity: 0.0
        z: 10

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
        }

        ColumnLayout {
            id: loginContent
            width: 360
            anchors.centerIn: parent
            spacing: 20

            Item {
                Layout.preferredWidth: 300
                Layout.preferredHeight: 306
                Layout.alignment: Qt.AlignHCenter

                // Hidden image source (loaded, but rendered via MultiEffect below)
                Image {
                    id: avatarImage
                    anchors.fill: parent
                    fillMode: Image.PreserveAspectCrop
                    smooth: true
                    asynchronous: true
                    visible: false  // MultiEffect renders it, not this element directly

                    property int fallbackStep: 0

                    function reloadAvatar() {
                        fallbackStep = 0;
                        source = Qt.resolvedUrl("assets/avatar.png");
                    }

                    Component.onCompleted: reloadAvatar()

                    Connections {
                        target: container
                        function onUserIndexChanged() {
                            avatarImage.reloadAvatar();
                        }
                    }

                    onStatusChanged: {
                        if (status === Image.Error) {
                            fallbackStep += 1;
                            if (fallbackStep === 1) {
                                source = Qt.resolvedUrl("assets/avatar.jpg");
                            } else if (fallbackStep === 2) {
                                source = Qt.resolvedUrl("assets/avatar.jpeg");
                            } else if (fallbackStep === 3) {
                                var icon = "";
                                if (typeof userModel !== "undefined" && userModel.count > 0) {
                                    var d = userModel.data(userModel.index(container.userIndex, 0), Qt.UserRole + 3);
                                    icon = d ? d.toString().trim() : "";
                                }
                                if (icon !== "") {
                                    source = icon;
                                } else {
                                    fallbackStep += 1;
                                    var username = "";
                                    if (typeof userModel !== "undefined" && userModel.count > 0) {
                                        var e = userModel.data(userModel.index(container.userIndex, 0), Qt.EditRole);
                                        var nr = userModel.data(userModel.index(container.userIndex, 0), Qt.UserRole + 1);
                                        username = e ? e.toString() : (nr ? nr.toString() : "");
                                    }
                                    if (!username) username = sddm.lastUser ? sddm.lastUser : "";
                                    if (username !== "")
                                        source = "file:///var/lib/AccountsService/icons/" + username;
                                }
                            }
                        }
                    }
                }

                // Mask shape for MultiEffect (must have layer.enabled: true for Qt6 MultiEffect)
                Rectangle {
                    id: avatarMask
                    anchors.fill: parent
                    radius: width / 2
                    color: "black"
                    visible: false
                    layer.enabled: true
                }

                // Letter fallback — shown when no image loaded
                Rectangle {
                    id: avatarFallback
                    anchors.fill: parent
                    color: surfaceColor
                    radius: width / 2
                    visible: avatarImage.status !== Image.Ready
                    border.color: "white"
                    border.width: 2

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
                        font.pixelSize: 96
                        font.family: config.fontFamily
                    }
                }

                // Circular clipped image via MultiEffect mask (true circle clip in Qt6)
                MultiEffect {
                    anchors.fill: parent
                    source: avatarImage
                    visible: avatarImage.status === Image.Ready
                    maskEnabled: true
                    maskSource: avatarMask
                }

                // White ring border on top
                Rectangle {
                    anchors.fill: parent
                    radius: width / 2
                    color: "transparent"
                    border.color: Qt.rgba(1, 1, 1, 0.7)
                    border.width: 2
                    visible: avatarImage.status === Image.Ready
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
                font.pixelSize: 38
                font.weight: Font.DemiBold
                font.family: config.fontFamily
            }

            Item {
                Layout.fillWidth: true
                Layout.preferredHeight: 44
                Layout.topMargin: 12

                TextField {
                    id: passwordField
                    anchors.fill: parent
                    echoMode: TextInput.Password
                    horizontalAlignment: Text.AlignLeft
                    leftPadding: 16
                    rightPadding: 48
                    font.pixelSize: 16
                    font.family: config.fontFamily
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
                        // Windows 11 acrylic/frosted glass password box
                        color: Qt.rgba(1, 1, 1, 0.08)
                        radius: 8
                        border.width: 1
                        border.color: Qt.rgba(1, 1, 1, 0.12)

                        // Bottom accent line (Win11 signature blue underline)
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            height: passwordField.activeFocus ? 2 : 0
                            color: "#60cdff"
                            radius: 1
                            Behavior on height { NumberAnimation { duration: 150 } }
                        }
                    }

                    Text {
                        text: "Password"
                        color: Qt.rgba(1, 1, 1, 0.6)
                        font.pixelSize: 16
                        font.family: config.fontFamily
                        visible: !parent.text
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.left: parent.left
                        anchors.leftMargin: 16
                    }

                    onAccepted: container.doLogin()

                    // Win11-style submit arrow button
                    Rectangle {
                        anchors.right: parent.right
                        anchors.verticalCenter: parent.verticalCenter
                        anchors.rightMargin: 4
                        width: 36
                        height: 36
                        radius: 6
                        color: submitBtnArea.containsMouse
                            ? (submitBtnArea.pressed ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.12))
                            : "transparent"

                        Text {
                            anchors.centerIn: parent
                            text: "→"
                            color: "white"
                            font.pixelSize: 20
                            opacity: 0.9
                        }

                        MouseArea {
                            id: submitBtnArea
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: container.doLogin()
                        }
                    }
                }
            }

            // Windows 11-style wrong password message
            Text {
                id: errorMessage
                Layout.alignment: Qt.AlignHCenter
                Layout.topMargin: 4
                text: "The password is incorrect. Try again."
                color: "#ffffff"
                font.pixelSize: 15
                font.family: config.fontFamily
                font.weight: Font.Normal
                opacity: loginState.isError ? 0.9 : 0.0
                visible: opacity > 0
                Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.InOutQuad } }

                Timer {
                    id: errorHideTimer
                    interval: 5000
                    running: loginState.isError
                    onTriggered: loginState.isError = false
                }

                Connections {
                    target: passwordField
                    function onTextChanged() {
                        if (loginState.isError && passwordField.text.length > 0) {
                            loginState.isError = false
                        }
                    }
                }
            }

            Rectangle {
                Layout.alignment: Qt.AlignHCenter
                Layout.preferredWidth: signInText.width + 32
                Layout.preferredHeight: 36
                visible: (typeof userModel !== "undefined" && userModel.count > 1) || (typeof sessionModel !== "undefined" && sessionModel.count > 1)
                radius: 6
                color: signInArea.containsMouse
                    ? (signInArea.pressed ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.12))
                    : Qt.rgba(1, 1, 1, 0.06)
                border.color: Qt.rgba(1, 1, 1, 0.1)
                border.width: 1

                Text {
                    id: signInText
                    anchors.centerIn: parent
                    text: "Sign-in options"
                    color: "white"
                    font.pixelSize: 14
                    font.family: config.fontFamily
                    opacity: 0.9
                }

                MouseArea {
                    id: signInArea
                    anchors.fill: parent
                    hoverEnabled: true
                    cursorShape: Qt.PointingHandCursor
                    onClicked: userPopup.open()
                }
            }

            Text {
                id: capsLockIndicator
                text: "Caps Lock is on"
                color: "white"
                font.pixelSize: 14
                font.family: config.fontFamily
                Layout.alignment: Qt.AlignHCenter
                visible: {
                    if (typeof keyboard !== "undefined") {
                        if (typeof keyboard.capsLock !== "undefined") return keyboard.capsLock;
                        if (typeof keyboard.capsLockActive !== "undefined") return keyboard.capsLockActive;
                    }
                    return false;
                }
                opacity: 0.85
            }

            Text {
                id: numLockIndicator
                text: "Num Lock is on"
                color: "white"
                font.pixelSize: 14
                font.family: config.fontFamily
                Layout.alignment: Qt.AlignHCenter
                visible: {
                    if (typeof keyboard !== "undefined" && typeof keyboard.numLock !== "undefined") return keyboard.numLock;
                    return false;
                }
                opacity: 0.85
            }
        }

        // Session indicator in bottom left
        Rectangle {
            anchors.bottom: parent.bottom
            anchors.left: parent.left
            anchors.margins: 30
            width: sessionLabel.width + 80
            height: 36
            color: sessionClickArea.containsMouse
                ? (sessionClickArea.pressed ? Qt.rgba(1, 1, 1, 0.08) : Qt.rgba(1, 1, 1, 0.12))
                : Qt.rgba(1, 1, 1, 0.06)
            radius: 5
            border.color: Qt.rgba(1, 1, 1, 0.1)
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
                hoverEnabled: true
                cursorShape: Qt.PointingHandCursor
                onClicked: sessionPopup.open()
            }
        }
    }

    Keys.onPressed: function(event) {
        if (container.lockScreenActive && !container.lockScreenAnimating) {
            container.transitionToLogin();
            event.accepted = true;
        }
    }

    Popup {
        id: userPopup
        width: 260
        height: (typeof userModel !== "undefined") ? Math.min(300, userModel.count * 50 + 20) : 100
        x: loginContent.x
        y: loginContent.y + loginContent.height + 5
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
        x: 30
        y: parent.height - height - 80
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

    // --- Post-login loading overlay with Win11 spinning dots ---
    // Stays visible after login success until desktop takes over (SDDM kills greeter)
    Rectangle {
        id: loginLoadingOverlay
        anchors.fill: parent
        color: "black"
        opacity: 0.0
        visible: false
        z: 1000  // Above everything

        function show() {
            visible = true;
            overlayFadeIn.start();
        }

        function hide() {
            overlayFadeOut.start();
        }

        NumberAnimation {
            id: overlayFadeIn
            target: loginLoadingOverlay
            property: "opacity"
            from: 0.0
            to: 1.0
            duration: 500
            easing.type: Easing.OutQuad
        }

        NumberAnimation {
            id: overlayFadeOut
            target: loginLoadingOverlay
            property: "opacity"
            from: 1.0
            to: 0.0
            duration: 400
            easing.type: Easing.InQuad
            onFinished: loginLoadingOverlay.visible = false
        }
    }
}
