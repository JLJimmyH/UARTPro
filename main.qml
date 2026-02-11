import QtQuick
import QtQuick.Controls
import QtQuick.Layouts

Window {
    id: root
    width: 1200
    height: 800
    minimumWidth: 900
    minimumHeight: 600
    visible: true
    title: "UART PRO // SERIAL TERMINAL v0.1"
    color: colorBg
    flags: Qt.FramelessWindowHint | Qt.Window

    // ── Frameless window state ────────────────────────────────────
    property bool isMaximized: false
    property rect restoreGeometry: Qt.rect(x, y, width, height)

    onVisibilityChanged: {
        if (visibility === Window.Maximized)
            isMaximized = true
        else if (visibility === Window.Windowed)
            isMaximized = false
    }

    function toggleMaximize() {
        if (isMaximized) {
            root.showNormal()
        } else {
            restoreGeometry = Qt.rect(root.x, root.y, root.width, root.height)
            root.showMaximized()
        }
    }
    function minimizeWindow() { root.showMinimized() }
    function closeWindow()    { root.close() }

    // ── Design Tokens ──────────────────────────────────────────────
    readonly property color colorBg:              "#0a0a0f"
    readonly property color colorFg:              "#e0e0e0"
    readonly property color colorCard:            "#12121a"
    readonly property color colorMuted:           "#1c1c2e"
    readonly property color colorMutedFg:         "#6b7280"
    readonly property color colorAccent:          "#00ff88"
    readonly property color colorAccentSecondary: "#ff00ff"
    readonly property color colorAccentTertiary:  "#00d4ff"
    readonly property color colorBorder:          "#2a2a3a"
    readonly property color colorDestructive:     "#ff3366"
    readonly property string fontMono:            "Consolas"

    // ── App State ──────────────────────────────────────────────────
    property bool hexDisplayMode: false
    property bool autoScroll: true
    property bool showTimestamp: true
    property bool hexSendMode: false

    // ── Baud / DataBits / StopBits / Parity models ────────────────
    readonly property var baudRates:  [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    readonly property var dataBitsList: [8, 7, 6, 5]
    readonly property var stopBitsList: [1, 2]
    readonly property var parityList:   ["None", "Even", "Odd"]
    readonly property var lineEndings:  ["None", "CR", "LF", "CR+LF"]

    // ══════════════════════════════════════════════════════════════
    // BACKGROUND — circuit grid pattern
    // ══════════════════════════════════════════════════════════════
    Canvas {
        id: bgGridCanvas
        anchors.fill: parent
        z: 0
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.strokeStyle = "rgba(0, 255, 136, 0.025)"
            ctx.lineWidth = 1
            var gs = 50
            for (var x = 0; x <= width; x += gs) {
                ctx.beginPath(); ctx.moveTo(x, 0); ctx.lineTo(x, height); ctx.stroke()
            }
            for (var y = 0; y <= height; y += gs) {
                ctx.beginPath(); ctx.moveTo(0, y); ctx.lineTo(width, y); ctx.stroke()
            }
        }
        Component.onCompleted: requestPaint()
        Connections {
            target: root
            function onWidthChanged()  { bgGridCanvas.requestPaint() }
            function onHeightChanged() { bgGridCanvas.requestPaint() }
        }
    }

    // Corner accent decorations (HUD style)
    Repeater {
        model: 4
        Item {
            z: 2
            readonly property bool isRight:  index % 2 === 1
            readonly property bool isBottom: index >= 2
            x: isRight  ? root.width - 30 : 0
            y: isBottom ? root.height - 30 : 0
            Rectangle {
                width: 30; height: 1
                color: root.colorAccent; opacity: 0.3
                anchors.left: parent.isRight ? undefined : parent.left
                anchors.right: parent.isRight ? parent.right : undefined
                y: parent.isBottom ? 29 : 0
            }
            Rectangle {
                width: 1; height: 30
                color: root.colorAccent; opacity: 0.3
                x: parent.isRight ? 29 : 0
                anchors.top: parent.isBottom ? undefined : parent.top
                anchors.bottom: parent.isBottom ? parent.bottom : undefined
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // MAIN LAYOUT
    // ══════════════════════════════════════════════════════════════
    ColumnLayout {
        anchors.fill: parent
        spacing: 0
        z: 1

        // ── HEADER BAR (custom title bar) ───────────────────────────
        Rectangle {
            id: titleBar
            Layout.fillWidth: true
            Layout.preferredHeight: 52
            color: root.colorCard
            border.color: root.colorBorder
            border.width: 1

            // Drag to move window
            DragHandler {
                target: null
                onActiveChanged: if (active) root.startSystemMove()
            }
            // Double-tap to maximize/restore
            TapHandler {
                onDoubleTapped: root.toggleMaximize()
                gesturePolicy: TapHandler.DragThreshold
            }

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 20
                anchors.rightMargin: 0
                spacing: 12

                // Glitch title
                Item {
                    Layout.preferredWidth: 260
                    Layout.fillHeight: true

                    // Magenta ghost
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: glitchAnim.offset
                        text: "UART PRO"
                        font.family: root.fontMono
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: 8
                        color: root.colorAccentSecondary
                        opacity: 0.5
                    }
                    // Cyan ghost
                    Text {
                        anchors.centerIn: parent
                        anchors.horizontalCenterOffset: -glitchAnim.offset
                        text: "UART PRO"
                        font.family: root.fontMono
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: 8
                        color: root.colorAccentTertiary
                        opacity: 0.5
                    }
                    // Main text
                    Text {
                        anchors.centerIn: parent
                        text: "UART PRO"
                        font.family: root.fontMono
                        font.pixelSize: 22
                        font.bold: true
                        font.letterSpacing: 8
                        color: root.colorFg
                    }

                    QtObject {
                        id: glitchAnim
                        property real offset: 0
                    }
                    SequentialAnimation {
                        running: true
                        loops: Animation.Infinite
                        PauseAnimation { duration: 5000 }
                        NumberAnimation { target: glitchAnim; property: "offset"; to: 3; duration: 50; easing.type: Easing.InOutQuad }
                        NumberAnimation { target: glitchAnim; property: "offset"; to: -1; duration: 30 }
                        NumberAnimation { target: glitchAnim; property: "offset"; to: 0; duration: 50 }
                        PauseAnimation { duration: 80 }
                        NumberAnimation { target: glitchAnim; property: "offset"; to: -2; duration: 40 }
                        NumberAnimation { target: glitchAnim; property: "offset"; to: 1; duration: 30 }
                        NumberAnimation { target: glitchAnim; property: "offset"; to: 0; duration: 60 }
                    }
                }

                // Subtitle
                Text {
                    text: "// SERIAL TERMINAL INTERFACE"
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: root.colorMutedFg
                }

                Item { Layout.fillWidth: true }

                // Connection status indicator
                Row {
                    spacing: 8
                    Rectangle {
                        id: statusDot
                        width: 8; height: 8; radius: 4
                        anchors.verticalCenter: parent.verticalCenter
                        color: serialManager.connected ? root.colorAccent : root.colorDestructive

                        SequentialAnimation on opacity {
                            running: true
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 800; easing.type: Easing.InOutSine }
                            NumberAnimation { to: 1.0; duration: 800; easing.type: Easing.InOutSine }
                        }
                    }
                    Text {
                        anchors.verticalCenter: parent.verticalCenter
                        text: serialManager.connected ? "ONLINE" : "OFFLINE"
                        font.family: root.fontMono
                        font.pixelSize: 11
                        font.letterSpacing: 2
                        font.bold: true
                        color: serialManager.connected ? root.colorAccent : root.colorMutedFg
                    }
                }

                // ── Separator before window controls ─────────
                Rectangle {
                    width: 1
                    Layout.fillHeight: true
                    Layout.topMargin: 12
                    Layout.bottomMargin: 12
                    color: root.colorBorder
                }

                // ── Window control buttons ───────────────────
                Row {
                    spacing: 0

                    // Minimize
                    Rectangle {
                        width: 46; height: 52
                        color: minimizeMa.containsMouse ? root.colorMuted : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // ─ horizontal line icon
                        Rectangle {
                            width: 12; height: 1
                            anchors.centerIn: parent
                            color: minimizeMa.containsMouse ? root.colorAccentTertiary : root.colorMutedFg
                            Behavior on color { ColorAnimation { duration: 100 } }
                        }

                        MouseArea {
                            id: minimizeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.minimizeWindow()
                        }
                    }

                    // Maximize / Restore
                    Rectangle {
                        width: 46; height: 52
                        color: maximizeMa.containsMouse ? root.colorMuted : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // □ square icon (maximize) or ⧉ overlapping squares (restore)
                        Item {
                            anchors.centerIn: parent
                            width: 12; height: 12
                            visible: !root.isMaximized
                            Rectangle {
                                anchors.fill: parent
                                color: "transparent"
                                border.width: 1
                                border.color: maximizeMa.containsMouse ? root.colorAccent : root.colorMutedFg
                                Behavior on border.color { ColorAnimation { duration: 100 } }
                            }
                        }
                        Item {
                            anchors.centerIn: parent
                            width: 12; height: 12
                            visible: root.isMaximized
                            Rectangle {
                                x: 2; y: 0; width: 9; height: 9
                                color: "transparent"
                                border.width: 1
                                border.color: maximizeMa.containsMouse ? root.colorAccent : root.colorMutedFg
                                Behavior on border.color { ColorAnimation { duration: 100 } }
                            }
                            Rectangle {
                                x: 0; y: 3; width: 9; height: 9
                                color: root.colorCard
                                border.width: 1
                                border.color: maximizeMa.containsMouse ? root.colorAccent : root.colorMutedFg
                                Behavior on border.color { ColorAnimation { duration: 100 } }
                            }
                        }

                        MouseArea {
                            id: maximizeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.toggleMaximize()
                        }
                    }

                    // Close
                    Rectangle {
                        width: 46; height: 52
                        color: closeMa.containsMouse ? root.colorDestructive : "transparent"
                        Behavior on color { ColorAnimation { duration: 100 } }

                        // ✕ cross icon
                        Item {
                            anchors.centerIn: parent
                            width: 14; height: 14
                            Rectangle {
                                width: 16; height: 1
                                anchors.centerIn: parent
                                rotation: 45
                                antialiasing: true
                                color: closeMa.containsMouse ? "#ffffff" : root.colorMutedFg
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                            Rectangle {
                                width: 16; height: 1
                                anchors.centerIn: parent
                                rotation: -45
                                antialiasing: true
                                color: closeMa.containsMouse ? "#ffffff" : root.colorMutedFg
                                Behavior on color { ColorAnimation { duration: 100 } }
                            }
                        }

                        MouseArea {
                            id: closeMa
                            anchors.fill: parent
                            hoverEnabled: true
                            onClicked: root.closeWindow()
                        }
                    }
                }
            }
        }

        // ── CONTENT AREA ──────────────────────────────────────────
        RowLayout {
            Layout.fillWidth: true
            Layout.fillHeight: true
            spacing: 0

            // ════════════════════════════════════════════════════════
            // LEFT PANEL — Connection Settings
            // ════════════════════════════════════════════════════════
            Rectangle {
                Layout.preferredWidth: 260
                Layout.fillHeight: true
                color: root.colorCard
                border.color: root.colorBorder
                border.width: 1

                Flickable {
                    anchors.fill: parent
                    anchors.margins: 16
                    contentHeight: leftCol.height
                    clip: true
                    boundsBehavior: Flickable.StopAtBounds

                    ColumnLayout {
                        id: leftCol
                        width: parent.width
                        spacing: 10

                        // Section: CONNECTION
                        Row {
                            spacing: 0
                            Text {
                                text: "> CONNECTION"
                                font.family: root.fontMono
                                font.pixelSize: 11
                                font.letterSpacing: 2
                                font.bold: true
                                color: root.colorAccent
                            }
                            // Blinking cursor
                            Text {
                                text: "_"
                                font.family: root.fontMono
                                font.pixelSize: 11
                                font.bold: true
                                color: root.colorAccent
                                SequentialAnimation on opacity {
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0; duration: 0 }
                                    PauseAnimation { duration: 530 }
                                    NumberAnimation { to: 1; duration: 0 }
                                    PauseAnimation { duration: 530 }
                                }
                            }
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        // PORT
                        Text {
                            text: "PORT"
                            font.family: root.fontMono; font.pixelSize: 10
                            font.letterSpacing: 2; color: root.colorMutedFg
                        }
                        CyberComboBox {
                            id: portCombo
                            Layout.fillWidth: true
                            model: serialManager.availablePorts
                            accentColor: root.colorAccent
                        }

                        // BAUD RATE
                        Text {
                            text: "BAUD RATE"
                            font.family: root.fontMono; font.pixelSize: 10
                            font.letterSpacing: 2; color: root.colorMutedFg
                        }
                        CyberComboBox {
                            id: baudCombo
                            Layout.fillWidth: true
                            model: root.baudRates
                            currentIndex: 4  // default 115200
                            accentColor: root.colorAccent
                        }

                        // DATA BITS
                        Text {
                            text: "DATA BITS"
                            font.family: root.fontMono; font.pixelSize: 10
                            font.letterSpacing: 2; color: root.colorMutedFg
                        }
                        CyberComboBox {
                            id: dataBitsCombo
                            Layout.fillWidth: true
                            model: root.dataBitsList
                            currentIndex: 0  // default 8
                            accentColor: root.colorAccent
                        }

                        // STOP BITS
                        Text {
                            text: "STOP BITS"
                            font.family: root.fontMono; font.pixelSize: 10
                            font.letterSpacing: 2; color: root.colorMutedFg
                        }
                        CyberComboBox {
                            id: stopBitsCombo
                            Layout.fillWidth: true
                            model: root.stopBitsList
                            currentIndex: 0  // default 1
                            accentColor: root.colorAccent
                        }

                        // PARITY
                        Text {
                            text: "PARITY"
                            font.family: root.fontMono; font.pixelSize: 10
                            font.letterSpacing: 2; color: root.colorMutedFg
                        }
                        CyberComboBox {
                            id: parityCombo
                            Layout.fillWidth: true
                            model: root.parityList
                            currentIndex: 0  // default None
                            accentColor: root.colorAccent
                        }

                        Item { height: 4 }

                        // Connect / Disconnect button
                        CyberButton {
                            Layout.fillWidth: true
                            text: serialManager.connected ? "DISCONNECT" : "CONNECT"
                            accentColor: serialManager.connected ? root.colorDestructive : root.colorAccent
                            glowing: serialManager.connected
                            enabled: !serialManager.connected || serialManager.connected
                            onClicked: {
                                if (serialManager.connected) {
                                    serialManager.disconnectPort()
                                } else {
                                    if (portCombo.currentIndex < 0) {
                                        addTerminalEntry("--:--:--.---", "No port selected", "", "error")
                                        return
                                    }
                                    var ok = serialManager.connectToPort(
                                        portCombo.currentText,
                                        parseInt(baudCombo.currentText),
                                        parseInt(dataBitsCombo.currentText),
                                        parseInt(stopBitsCombo.currentText),
                                        parityCombo.currentIndex
                                    )
                                    if (!ok) {
                                        addTerminalEntry(
                                            Qt.formatDateTime(new Date(), "HH:mm:ss.zzz"),
                                            "Failed to open port", "", "error"
                                        )
                                    }
                                }
                            }
                        }

                        Item { height: 8 }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        // Section: OPTIONS
                        Text {
                            text: "> OPTIONS"
                            font.family: root.fontMono; font.pixelSize: 11
                            font.letterSpacing: 2; font.bold: true
                            color: root.colorAccentTertiary
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        CyberCheckBox {
                            text: "HEX DISPLAY"
                            checked: root.hexDisplayMode
                            accentColor: root.colorAccentTertiary
                            onCheckedChanged: root.hexDisplayMode = checked
                        }
                        CyberCheckBox {
                            text: "AUTO SCROLL"
                            checked: root.autoScroll
                            accentColor: root.colorAccentTertiary
                            onCheckedChanged: root.autoScroll = checked
                        }
                        CyberCheckBox {
                            text: "TIMESTAMP"
                            checked: root.showTimestamp
                            accentColor: root.colorAccentTertiary
                            onCheckedChanged: root.showTimestamp = checked
                        }

                        Item { height: 8 }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        // Section: ACTIONS
                        Text {
                            text: "> ACTIONS"
                            font.family: root.fontMono; font.pixelSize: 11
                            font.letterSpacing: 2; font.bold: true
                            color: root.colorAccentSecondary
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        CyberButton {
                            Layout.fillWidth: true
                            text: "REFRESH PORTS"
                            accentColor: root.colorAccentTertiary
                            onClicked: serialManager.refreshPorts()
                        }
                        CyberButton {
                            Layout.fillWidth: true
                            text: "CLEAR TERMINAL"
                            accentColor: root.colorAccentSecondary
                            onClicked: terminalModel.clear()
                        }

                        Item { Layout.fillHeight: true }
                    }
                }
            }

            // ════════════════════════════════════════════════════════
            // RIGHT PANEL — Terminal + Send
            // ════════════════════════════════════════════════════════
            Rectangle {
                Layout.fillWidth: true
                Layout.fillHeight: true
                color: root.colorBg
                border.color: root.colorBorder
                border.width: 1

                ColumnLayout {
                    anchors.fill: parent
                    spacing: 0

                    // Terminal header bar
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 36
                        color: root.colorCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            // Traffic light dots
                            Row {
                                spacing: 6
                                Repeater {
                                    model: ["#ff3366", "#ffaa00", "#00ff88"]
                                    Rectangle {
                                        width: 10; height: 10; radius: 5
                                        color: modelData; opacity: 0.8
                                    }
                                }
                            }

                            Text {
                                text: "// TERMINAL OUTPUT"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 2
                                color: root.colorMutedFg
                            }

                            Item { Layout.fillWidth: true }

                            Text {
                                text: root.hexDisplayMode ? "[HEX]" : "[ASCII]"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                font.bold: true
                                color: root.colorAccentTertiary
                            }

                            Text {
                                text: terminalModel.count + " ENTRIES"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                color: root.colorMutedFg
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                    // Terminal output area
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListView {
                            id: terminalView
                            anchors.fill: parent
                            anchors.margins: 8
                            clip: true
                            spacing: 2
                            model: ListModel { id: terminalModel }
                            boundsBehavior: Flickable.StopAtBounds

                            ScrollBar.vertical: ScrollBar {
                                policy: ScrollBar.AsNeeded
                                contentItem: Rectangle {
                                    implicitWidth: 6
                                    color: root.colorAccent
                                    opacity: 0.4
                                    radius: 3
                                }
                                background: Rectangle {
                                    implicitWidth: 6
                                    color: "transparent"
                                }
                            }

                            delegate: Row {
                                width: terminalView.width - 16
                                spacing: 8
                                height: Math.max(dataText.contentHeight, 18)

                                // Timestamp
                                Text {
                                    id: tsText
                                    visible: root.showTimestamp
                                    text: model.timestamp
                                    font.family: root.fontMono
                                    font.pixelSize: 12
                                    color: root.colorMutedFg
                                    width: visible ? 90 : 0
                                    anchors.top: parent.top
                                }

                                // Direction prefix
                                Text {
                                    id: prefixText
                                    text: {
                                        switch (model.type) {
                                        case "rx":     return "RX>"
                                        case "tx":     return "TX>"
                                        case "system": return "SYS>"
                                        case "error":  return "ERR>"
                                        default:       return ">"
                                        }
                                    }
                                    font.family: root.fontMono
                                    font.pixelSize: 12
                                    font.bold: true
                                    color: model.msgColor
                                    width: 36
                                    anchors.top: parent.top
                                }

                                // Data content
                                Text {
                                    id: dataText
                                    text: root.hexDisplayMode && model.hexData !== "" ? model.hexData : model.data
                                    font.family: root.fontMono
                                    font.pixelSize: 12
                                    color: root.colorFg
                                    width: parent.width - tsText.width - prefixText.width - 24
                                    wrapMode: Text.WrapAnywhere
                                    anchors.top: parent.top
                                }
                            }

                            // Empty state
                            Text {
                                anchors.centerIn: parent
                                visible: terminalModel.count === 0
                                text: "AWAITING DATA STREAM..."
                                font.family: root.fontMono
                                font.pixelSize: 13
                                font.letterSpacing: 2
                                color: root.colorMutedFg
                                opacity: 0.5
                            }
                        }

                        // Scanline overlay on terminal
                        Canvas {
                            anchors.fill: parent
                            z: 10
                            opacity: 0.04
                            onPaint: {
                                var ctx = getContext("2d")
                                ctx.clearRect(0, 0, width, height)
                                ctx.fillStyle = "#000000"
                                for (var y = 0; y < height; y += 4)
                                    ctx.fillRect(0, y, width, 1)
                            }
                            Component.onCompleted: requestPaint()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                    // ── SEND AREA ──────────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 52
                        color: root.colorCard

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 8

                            // HEX/ASCII toggle
                            CyberButton {
                                Layout.preferredWidth: 65
                                text: root.hexSendMode ? "HEX" : "ASCII"
                                accentColor: root.hexSendMode ? root.colorAccentSecondary : root.colorAccentTertiary
                                onClicked: root.hexSendMode = !root.hexSendMode
                                font.pixelSize: 10
                            }

                            // Input field
                            CyberTextField {
                                id: sendInput
                                Layout.fillWidth: true
                                placeholderText: root.hexSendMode ? "48 65 6C 6C 6F..." : "Enter data to transmit..."
                                accentColor: root.colorAccent
                                enabled: serialManager.connected

                                Keys.onReturnPressed: sendCurrentData()
                                Keys.onEnterPressed: sendCurrentData()
                            }

                            // Line ending selector
                            CyberComboBox {
                                id: lineEndingCombo
                                Layout.preferredWidth: 85
                                model: root.lineEndings
                                currentIndex: 0
                                accentColor: root.colorMutedFg
                                font.pixelSize: 10
                            }

                            // Transmit button
                            CyberButton {
                                Layout.preferredWidth: 110
                                text: "TRANSMIT"
                                accentColor: root.colorAccent
                                glowing: serialManager.connected
                                enabled: serialManager.connected
                                onClicked: sendCurrentData()
                            }
                        }
                    }
                }
            }
        }

        // ── STATUS BAR ────────────────────────────────────────────
        Rectangle {
            Layout.fillWidth: true
            Layout.preferredHeight: 30
            color: root.colorCard
            border.color: root.colorBorder
            border.width: 1

            RowLayout {
                anchors.fill: parent
                anchors.leftMargin: 16
                anchors.rightMargin: 16
                spacing: 24

                // Port info
                Text {
                    text: serialManager.connected
                          ? ("PORT: " + portCombo.currentText.split(" - ")[0]
                             + " @ " + baudCombo.currentText + " bps")
                          : "PORT: ---"
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: serialManager.connected ? root.colorAccent : root.colorMutedFg
                }

                // Separator
                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: root.colorBorder }

                Text {
                    text: "RX: " + formatBytes(serialManager.rxBytes)
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: root.colorAccentTertiary
                }

                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: root.colorBorder }

                Text {
                    text: "TX: " + formatBytes(serialManager.txBytes)
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: root.colorAccentSecondary
                }

                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: root.colorBorder }

                // Uptime
                Text {
                    text: "UPTIME: " + formatUptime(uptimeTimer.seconds)
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: root.colorMutedFg
                }

                Item { Layout.fillWidth: true }

                Text {
                    text: "UART PRO v0.1"
                    font.family: root.fontMono
                    font.pixelSize: 9
                    font.letterSpacing: 1
                    color: root.colorMutedFg
                    opacity: 0.5
                }
            }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // SCANLINE OVERLAY (full window)
    // ══════════════════════════════════════════════════════════════
    Canvas {
        id: scanlineCanvas
        anchors.fill: parent
        z: 100
        opacity: 0.03
        onPaint: {
            var ctx = getContext("2d")
            ctx.clearRect(0, 0, width, height)
            ctx.fillStyle = "#000000"
            for (var y = 0; y < height; y += 3)
                ctx.fillRect(0, y, width, 1)
        }
        Component.onCompleted: requestPaint()
        Connections {
            target: root
            function onWidthChanged()  { scanlineCanvas.requestPaint() }
            function onHeightChanged() { scanlineCanvas.requestPaint() }
        }
    }

    // ══════════════════════════════════════════════════════════════
    // RESIZE HANDLES (frameless window)
    // ══════════════════════════════════════════════════════════════
    // Edges
    MouseArea {
        z: 200; visible: !root.isMaximized
        width: 5; anchors { left: parent.left; top: parent.top; bottom: parent.bottom; topMargin: 5; bottomMargin: 5 }
        cursorShape: Qt.SizeHorCursor
        onPressed: root.startSystemResize(Qt.LeftEdge)
    }
    MouseArea {
        z: 200; visible: !root.isMaximized
        width: 5; anchors { right: parent.right; top: parent.top; bottom: parent.bottom; topMargin: 5; bottomMargin: 5 }
        cursorShape: Qt.SizeHorCursor
        onPressed: root.startSystemResize(Qt.RightEdge)
    }
    MouseArea {
        z: 200; visible: !root.isMaximized
        height: 5; anchors { top: parent.top; left: parent.left; right: parent.right; leftMargin: 5; rightMargin: 5 }
        cursorShape: Qt.SizeVerCursor
        onPressed: root.startSystemResize(Qt.TopEdge)
    }
    MouseArea {
        z: 200; visible: !root.isMaximized
        height: 5; anchors { bottom: parent.bottom; left: parent.left; right: parent.right; leftMargin: 5; rightMargin: 5 }
        cursorShape: Qt.SizeVerCursor
        onPressed: root.startSystemResize(Qt.BottomEdge)
    }
    // Corners
    MouseArea {
        z: 200; visible: !root.isMaximized
        width: 8; height: 8; anchors { left: parent.left; top: parent.top }
        cursorShape: Qt.SizeFDiagCursor
        onPressed: root.startSystemResize(Qt.LeftEdge | Qt.TopEdge)
    }
    MouseArea {
        z: 200; visible: !root.isMaximized
        width: 8; height: 8; anchors { right: parent.right; top: parent.top }
        cursorShape: Qt.SizeBDiagCursor
        onPressed: root.startSystemResize(Qt.RightEdge | Qt.TopEdge)
    }
    MouseArea {
        z: 200; visible: !root.isMaximized
        width: 8; height: 8; anchors { left: parent.left; bottom: parent.bottom }
        cursorShape: Qt.SizeBDiagCursor
        onPressed: root.startSystemResize(Qt.LeftEdge | Qt.BottomEdge)
    }
    MouseArea {
        z: 200; visible: !root.isMaximized
        width: 8; height: 8; anchors { right: parent.right; bottom: parent.bottom }
        cursorShape: Qt.SizeFDiagCursor
        onPressed: root.startSystemResize(Qt.RightEdge | Qt.BottomEdge)
    }

    // ══════════════════════════════════════════════════════════════
    // TIMERS & CONNECTIONS
    // ══════════════════════════════════════════════════════════════
    Timer {
        id: uptimeTimer
        interval: 1000
        running: serialManager.connected
        repeat: true
        property int seconds: 0
        onTriggered: seconds++
    }

    Connections {
        target: serialManager

        function onConnectedChanged() {
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            if (serialManager.connected) {
                uptimeTimer.seconds = 0
                addTerminalEntry(ts, "Connection established — "
                    + portCombo.currentText.split(" - ")[0] + " @ "
                    + baudCombo.currentText + " bps", "", "system")
            } else {
                addTerminalEntry(ts, "Connection closed", "", "system")
            }
        }

        function onDataReceived(timestamp, asciiData, hexData) {
            addTerminalEntry(timestamp, asciiData, hexData, "rx")
        }

        function onErrorOccurred(error) {
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            addTerminalEntry(ts, error, "", "error")
        }
    }

    // ══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ══════════════════════════════════════════════════════════════
    function addTerminalEntry(timestamp, data, hexData, type) {
        var color
        switch (type) {
        case "rx":     color = "#00ff88"; break
        case "tx":     color = "#00d4ff"; break
        case "system": color = "#ff00ff"; break
        case "error":  color = "#ff3366"; break
        default:       color = "#e0e0e0"
        }
        terminalModel.append({
            timestamp: timestamp,
            data: data,
            hexData: hexData || "",
            type: type,
            msgColor: color
        })
        if (root.autoScroll)
            terminalView.positionViewAtEnd()
    }

    function sendCurrentData() {
        var data = sendInput.text
        if (data.length === 0) return

        // Append line ending
        var endings = ["", "\r", "\n", "\r\n"]
        var toSend = data + endings[lineEndingCombo.currentIndex]

        if (serialManager.sendData(toSend, root.hexSendMode)) {
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            var displayData = root.hexSendMode ? data : data
            addTerminalEntry(ts, displayData, "", "tx")
            sendInput.text = ""
        }
    }

    function formatBytes(bytes) {
        if (bytes < 1024) return bytes + " B"
        if (bytes < 1048576) return (bytes / 1024).toFixed(1) + " KB"
        return (bytes / 1048576).toFixed(2) + " MB"
    }

    function formatUptime(totalSeconds) {
        var h = Math.floor(totalSeconds / 3600)
        var m = Math.floor((totalSeconds % 3600) / 60)
        var s = totalSeconds % 60
        return String(h).padStart(2, '0') + ":"
             + String(m).padStart(2, '0') + ":"
             + String(s).padStart(2, '0')
    }

    // Boot sequence on startup
    Component.onCompleted: {
        var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
        addTerminalEntry(ts, "UART PRO v0.1 // SERIAL TERMINAL INTERFACE", "", "system")
        addTerminalEntry(ts, "System initialized. Ready for connection.", "", "system")
        addTerminalEntry(ts, "Select a port and click CONNECT to begin.", "", "system")
        serialManager.refreshPorts()
    }
}
