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

    // ── Theme System ────────────────────────────────────────────────
    property int currentTheme: 0
    readonly property var themes: [
        {
            name: "CYBER",
            bg: "#0a0a0f", fg: "#e0e0e0", card: "#12121a", muted: "#1c1c2e",
            mutedFg: "#6b7280", accent: "#00ff88", accentSecondary: "#ff00ff",
            accentTertiary: "#00d4ff", border: "#2a2a3a", destructive: "#ff3366"
        },
        {
            name: "AMBER",
            bg: "#0a0800", fg: "#ffb000", card: "#12100a", muted: "#1c1a10",
            mutedFg: "#7a6b40", accent: "#ffb000", accentSecondary: "#ff6600",
            accentTertiary: "#ffdd00", border: "#2a2818", destructive: "#ff3300"
        }
    ]

    // ── Design Tokens ──────────────────────────────────────────────
    property color colorBg:              "#0a0a0f"
    property color colorFg:              "#e0e0e0"
    property color colorCard:            "#12121a"
    property color colorMuted:           "#1c1c2e"
    property color colorMutedFg:         "#6b7280"
    property color colorAccent:          "#00ff88"
    property color colorAccentSecondary: "#ff00ff"
    property color colorAccentTertiary:  "#00d4ff"
    property color colorBorder:          "#2a2a3a"
    property color colorDestructive:     "#ff3366"
    readonly property string fontMono:   "Consolas"

    function applyTheme(index) {
        var t = themes[index]
        currentTheme = index
        colorBg = t.bg
        colorFg = t.fg
        colorCard = t.card
        colorMuted = t.muted
        colorMutedFg = t.mutedFg
        colorAccent = t.accent
        colorAccentSecondary = t.accentSecondary
        colorAccentTertiary = t.accentTertiary
        colorBorder = t.border
        colorDestructive = t.destructive
        bgGridCanvas.requestPaint()
        scanlineCanvas.requestPaint()
    }

    // ── App State ──────────────────────────────────────────────────
    property bool hexDisplayMode: false
    property bool autoScroll: true
    property bool showTimestamp: true
    property bool hexSendMode: false

    // ── Selection & Keyword State ──────────────────────────────────
    property var terminalEntries: []
    property var selectedSet: ({})
    property int selectionVersion: 0
    property int keywordRevision: 0
    property int kwColorIndex: 0
    readonly property var kwPalette: ["#ff3366", "#ffaa00", "#00ff88", "#00d4ff",
                                      "#ff00ff", "#ffff00", "#ff6600", "#aa66ff"]

    // ── Baud / DataBits / StopBits / Parity models ────────────────
    readonly property var baudRates:  [9600, 19200, 38400, 57600, 115200, 230400, 460800, 921600]
    readonly property var dataBitsList: [8, 7, 6, 5]
    readonly property var stopBitsList: [1, 2]
    readonly property var parityList:   ["None", "Even", "Odd"]
    readonly property var lineEndings:  ["None", "CR", "LF", "CR+LF"]

    // ── Data Models ────────────────────────────────────────────────
    ListModel { id: keywordModel }
    ListModel { id: whitelistModel }
    ListModel { id: blacklistModel }

    // Hidden TextEdit for clipboard access
    TextEdit { id: clipHelper; visible: false }

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
            var c = root.colorAccent
            ctx.strokeStyle = Qt.rgba(c.r, c.g, c.b, 0.025)
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

    // ── Right-click context menu ──────────────────────────────────
    Menu {
        id: terminalContextMenu
        background: Rectangle {
            implicitWidth: 200
            color: root.colorCard
            border.color: root.colorAccent
            border.width: 1
        }
        MenuItem {
            text: "  COPY SELECTED"
            enabled: {
                root.selectionVersion
                var keys = Object.keys(root.selectedSet)
                return keys.length > 0
            }
            onTriggered: copySelectedEntries()
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: parent.enabled ? root.colorAccent : root.colorMutedFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }
        MenuItem {
            text: "  COPY ALL"
            onTriggered: copyAllEntries()
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: root.colorAccentTertiary
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }
        MenuItem {
            text: "  SELECT ALL"
            onTriggered: selectAllEntries()
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: root.colorFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }
        MenuItem {
            text: "  CLEAR SELECTION"
            onTriggered: clearSelection()
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: root.colorMutedFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
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

                // Theme switcher
                Rectangle {
                    width: themeLabel.width + 16
                    height: 26
                    color: themeMa.containsMouse ? root.colorMuted : "transparent"
                    border.color: themeMa.containsMouse ? root.colorAccent : root.colorBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Text {
                        id: themeLabel
                        anchors.centerIn: parent
                        text: "[" + root.themes[root.currentTheme].name + "]"
                        font.family: root.fontMono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        font.bold: true
                        color: themeMa.containsMouse ? root.colorAccent : root.colorMutedFg
                        Behavior on color { ColorAnimation { duration: 150 } }
                    }
                    MouseArea {
                        id: themeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: root.applyTheme((root.currentTheme + 1) % root.themes.length)
                    }
                }

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
                Layout.preferredWidth: 280
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
                            cardColor: root.colorCard; borderColor: root.colorBorder
                            fgColor: root.colorFg; bgColor: root.colorBg
                            mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
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
                            currentIndex: 7  // default 921600
                            accentColor: root.colorAccent
                            cardColor: root.colorCard; borderColor: root.colorBorder
                            fgColor: root.colorFg; bgColor: root.colorBg
                            mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
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
                            cardColor: root.colorCard; borderColor: root.colorBorder
                            fgColor: root.colorFg; bgColor: root.colorBg
                            mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
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
                            cardColor: root.colorCard; borderColor: root.colorBorder
                            fgColor: root.colorFg; bgColor: root.colorBg
                            mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
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
                            cardColor: root.colorCard; borderColor: root.colorBorder
                            fgColor: root.colorFg; bgColor: root.colorBg
                            mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
                        }

                        Item { height: 4 }

                        // Connect / Disconnect button
                        CyberButton {
                            Layout.fillWidth: true
                            text: serialManager.connected ? "DISCONNECT" : "CONNECT"
                            accentColor: serialManager.connected ? root.colorDestructive : root.colorAccent
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder
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
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder; mutedFgColor: root.colorMutedFg
                            onCheckedChanged: root.hexDisplayMode = checked
                        }
                        CyberCheckBox {
                            text: "AUTO SCROLL"
                            checked: root.autoScroll
                            accentColor: root.colorAccentTertiary
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder; mutedFgColor: root.colorMutedFg
                            onCheckedChanged: root.autoScroll = checked
                        }
                        CyberCheckBox {
                            text: "TIMESTAMP"
                            checked: root.showTimestamp
                            accentColor: root.colorAccentTertiary
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder; mutedFgColor: root.colorMutedFg
                            onCheckedChanged: root.showTimestamp = checked
                        }

                        Item { height: 8 }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        // ── Section: KEYWORDS ──────────────────────────
                        Text {
                            text: "> KEYWORDS"
                            font.family: root.fontMono; font.pixelSize: 11
                            font.letterSpacing: 2; font.bold: true
                            color: "#ffaa00"
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            CyberTextField {
                                id: kwInput
                                Layout.fillWidth: true
                                placeholderText: "keyword..."
                                accentColor: "#ffaa00"
                                cardColor: root.colorCard; borderColor: root.colorBorder
                                bgColor: root.colorBg; mutedFgColor: root.colorMutedFg
                                font.pixelSize: 11
                            }
                            CyberButton {
                                Layout.preferredWidth: 40
                                text: "+"
                                accentColor: "#ffaa00"
                                bgColor: root.colorBg; borderMutedColor: root.colorBorder
                                font.pixelSize: 14
                                onClicked: addKeyword(kwInput.text)
                            }
                        }

                        // Keyword list
                        Repeater {
                            model: keywordModel
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Rectangle {
                                    width: 12; height: 12
                                    color: model.color
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: model.text
                                    font.family: root.fontMono; font.pixelSize: 11
                                    color: model.color
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "✕"
                                    font.family: root.fontMono; font.pixelSize: 12
                                    font.bold: true
                                    color: root.colorDestructive
                                    opacity: kwDelMa.containsMouse ? 1.0 : 0.5
                                    MouseArea {
                                        id: kwDelMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            keywordModel.remove(index)
                                            root.keywordRevision++
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 4 }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        // ── Section: WHITELIST ─────────────────────────
                        Text {
                            text: "> WHITELIST"
                            font.family: root.fontMono; font.pixelSize: 11
                            font.letterSpacing: 2; font.bold: true
                            color: root.colorAccent
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            CyberTextField {
                                id: wlInput
                                Layout.fillWidth: true
                                placeholderText: "include..."
                                accentColor: root.colorAccent
                                cardColor: root.colorCard; borderColor: root.colorBorder
                                bgColor: root.colorBg; mutedFgColor: root.colorMutedFg
                                font.pixelSize: 11
                            }
                            CyberButton {
                                Layout.preferredWidth: 40
                                text: "+"
                                accentColor: root.colorAccent
                                bgColor: root.colorBg; borderMutedColor: root.colorBorder
                                font.pixelSize: 14
                                onClicked: addWhitelist(wlInput.text)
                            }
                        }

                        Repeater {
                            model: whitelistModel
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: "+"
                                    font.family: root.fontMono; font.pixelSize: 12
                                    font.bold: true
                                    color: root.colorAccent
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: model.text
                                    font.family: root.fontMono; font.pixelSize: 11
                                    color: root.colorAccent
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "✕"
                                    font.family: root.fontMono; font.pixelSize: 12
                                    font.bold: true
                                    color: root.colorDestructive
                                    opacity: wlDelMa.containsMouse ? 1.0 : 0.5
                                    MouseArea {
                                        id: wlDelMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            whitelistModel.remove(index)
                                            rebuildFilteredModel()
                                        }
                                    }
                                }
                            }
                        }

                        Item { height: 4 }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        // ── Section: BLACKLIST ─────────────────────────
                        Text {
                            text: "> BLACKLIST"
                            font.family: root.fontMono; font.pixelSize: 11
                            font.letterSpacing: 2; font.bold: true
                            color: root.colorDestructive
                        }

                        Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                        RowLayout {
                            Layout.fillWidth: true
                            spacing: 4
                            CyberTextField {
                                id: blInput
                                Layout.fillWidth: true
                                placeholderText: "exclude..."
                                accentColor: root.colorDestructive
                                cardColor: root.colorCard; borderColor: root.colorBorder
                                bgColor: root.colorBg; mutedFgColor: root.colorMutedFg
                                font.pixelSize: 11
                            }
                            CyberButton {
                                Layout.preferredWidth: 40
                                text: "+"
                                accentColor: root.colorDestructive
                                bgColor: root.colorBg; borderMutedColor: root.colorBorder
                                font.pixelSize: 14
                                onClicked: addBlacklist(blInput.text)
                            }
                        }

                        Repeater {
                            model: blacklistModel
                            delegate: RowLayout {
                                Layout.fillWidth: true
                                spacing: 6
                                Text {
                                    text: "−"
                                    font.family: root.fontMono; font.pixelSize: 14
                                    font.bold: true
                                    color: root.colorDestructive
                                }
                                Text {
                                    Layout.fillWidth: true
                                    text: model.text
                                    font.family: root.fontMono; font.pixelSize: 11
                                    color: root.colorDestructive
                                    elide: Text.ElideRight
                                }
                                Text {
                                    text: "✕"
                                    font.family: root.fontMono; font.pixelSize: 12
                                    font.bold: true
                                    color: root.colorDestructive
                                    opacity: blDelMa.containsMouse ? 1.0 : 0.5
                                    MouseArea {
                                        id: blDelMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            blacklistModel.remove(index)
                                            rebuildFilteredModel()
                                        }
                                    }
                                }
                            }
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
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder
                            onClicked: serialManager.refreshPorts()
                        }
                        CyberButton {
                            Layout.fillWidth: true
                            text: "COPY LOG"
                            accentColor: "#ffaa00"
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder
                            onClicked: {
                                var keys = Object.keys(root.selectedSet)
                                root.selectionVersion
                                if (keys.length > 0)
                                    copySelectedEntries()
                                else
                                    copyAllEntries()
                            }
                        }
                        CyberButton {
                            Layout.fillWidth: true
                            text: "CLEAR TERMINAL"
                            accentColor: root.colorAccentSecondary
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder
                            onClicked: {
                                terminalModel.clear()
                                root.terminalEntries = []
                                clearSelection()
                            }
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

                            // Filter indicator
                            Text {
                                visible: whitelistModel.count > 0 || blacklistModel.count > 0
                                text: "[FILTERED " + terminalModel.count + "/" + root.terminalEntries.length + "]"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                font.bold: true
                                color: "#ffaa00"
                            }

                            // Selection indicator
                            Text {
                                property int selCount: {
                                    root.selectionVersion
                                    return Object.keys(root.selectedSet).length
                                }
                                visible: selCount > 0
                                text: "[SEL " + selCount + "]"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                font.bold: true
                                color: root.colorAccentSecondary
                            }

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

                            delegate: Item {
                                width: terminalView.width - 16
                                height: Math.max(dataText.contentHeight, 18)

                                property bool isSelected: {
                                    root.selectionVersion
                                    return root.selectedSet.hasOwnProperty(model.entryIndex)
                                }

                                // Selection highlight
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    color: parent.isSelected ? root.colorAccent : "transparent"
                                    opacity: 0.1
                                }
                                Rectangle {
                                    anchors.fill: parent
                                    anchors.margins: -2
                                    color: "transparent"
                                    border.color: root.colorAccent
                                    border.width: parent.isSelected ? 1 : 0
                                    opacity: 0.3
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            terminalContextMenu.popup()
                                        } else {
                                            toggleSelection(model.entryIndex, mouse.modifiers & Qt.ControlModifier)
                                        }
                                    }
                                }

                                Row {
                                    anchors.fill: parent
                                    spacing: 8

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

                                    // Data content with keyword highlighting
                                    Text {
                                        id: dataText
                                        text: {
                                            root.keywordRevision
                                            var raw = root.hexDisplayMode && model.hexData !== "" ? model.hexData : model.data
                                            return highlightText(raw)
                                        }
                                        textFormat: Text.RichText
                                        font.family: root.fontMono
                                        font.pixelSize: 12
                                        color: root.colorFg
                                        width: parent.width - tsText.width - prefixText.width - 24
                                        wrapMode: Text.WrapAnywhere
                                        anchors.top: parent.top
                                    }
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
                                bgColor: root.colorBg; borderMutedColor: root.colorBorder
                                onClicked: root.hexSendMode = !root.hexSendMode
                                font.pixelSize: 10
                            }

                            // Input field
                            CyberTextField {
                                id: sendInput
                                Layout.fillWidth: true
                                placeholderText: root.hexSendMode ? "48 65 6C 6C 6F..." : "Enter data to transmit..."
                                accentColor: root.colorAccent
                                cardColor: root.colorCard; borderColor: root.colorBorder
                                bgColor: root.colorBg; mutedFgColor: root.colorMutedFg
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
                                cardColor: root.colorCard; borderColor: root.colorBorder
                                fgColor: root.colorFg; bgColor: root.colorBg
                                mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
                                font.pixelSize: 10
                            }

                            // Transmit button
                            CyberButton {
                                Layout.preferredWidth: 110
                                text: "TRANSMIT"
                                accentColor: root.colorAccent
                                bgColor: root.colorBg; borderMutedColor: root.colorBorder
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

    // ── Entry & Filter ──────────────────────────────────────────
    function addTerminalEntry(timestamp, data, hexData, type) {
        var color
        switch (type) {
        case "rx":     color = root.colorAccent.toString(); break
        case "tx":     color = root.colorAccentTertiary.toString(); break
        case "system": color = root.colorAccentSecondary.toString(); break
        case "error":  color = root.colorDestructive.toString(); break
        default:       color = root.colorFg.toString()
        }

        var entry = {
            timestamp: timestamp,
            data: data,
            hexData: hexData || "",
            type: type,
            msgColor: color,
            entryIndex: root.terminalEntries.length
        }

        var entries = root.terminalEntries
        entries.push(entry)
        root.terminalEntries = entries

        if (passesFilter(entry)) {
            terminalModel.append(entry)
        }

        if (root.autoScroll)
            terminalView.positionViewAtEnd()
    }

    function passesFilter(entry) {
        // system and error messages always pass
        if (entry.type === "system" || entry.type === "error")
            return true

        var text = entry.data.toLowerCase()

        // Whitelist: if any whitelist entries exist, data must contain at least one
        if (whitelistModel.count > 0) {
            var wlPass = false
            for (var i = 0; i < whitelistModel.count; i++) {
                if (text.indexOf(whitelistModel.get(i).text.toLowerCase()) >= 0) {
                    wlPass = true
                    break
                }
            }
            if (!wlPass) return false
        }

        // Blacklist: data must not contain any blacklist entry
        for (var j = 0; j < blacklistModel.count; j++) {
            if (text.indexOf(blacklistModel.get(j).text.toLowerCase()) >= 0)
                return false
        }

        return true
    }

    function rebuildFilteredModel() {
        terminalModel.clear()
        clearSelection()
        for (var i = 0; i < root.terminalEntries.length; i++) {
            var entry = root.terminalEntries[i]
            if (passesFilter(entry)) {
                terminalModel.append(entry)
            }
        }
        if (root.autoScroll)
            terminalView.positionViewAtEnd()
    }

    // ── Keyword Highlighting ────────────────────────────────────
    function escapeHtml(str) {
        return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function escapeRegex(str) {
        return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    }

    function highlightText(raw) {
        if (keywordModel.count === 0)
            return escapeHtml(raw)

        var html = escapeHtml(raw)

        for (var i = 0; i < keywordModel.count; i++) {
            var kw = keywordModel.get(i)
            var escaped = escapeRegex(escapeHtml(kw.text))
            var re = new RegExp("(" + escaped + ")", "gi")
            html = html.replace(re, "<span style='background-color:" + kw.color + ";color:" + root.colorBg + ";font-weight:bold;'>$1</span>")
        }

        return html
    }

    // ── Selection ───────────────────────────────────────────────
    function toggleSelection(entryIdx, ctrlHeld) {
        var s = root.selectedSet
        if (ctrlHeld) {
            if (s.hasOwnProperty(entryIdx))
                delete s[entryIdx]
            else
                s[entryIdx] = true
        } else {
            s = {}
            s[entryIdx] = true
        }
        root.selectedSet = s
        root.selectionVersion++
    }

    function clearSelection() {
        root.selectedSet = {}
        root.selectionVersion++
    }

    function selectAllEntries() {
        var s = {}
        for (var i = 0; i < terminalModel.count; i++) {
            s[terminalModel.get(i).entryIndex] = true
        }
        root.selectedSet = s
        root.selectionVersion++
    }

    // ── Copy ────────────────────────────────────────────────────
    function buildEntryText(entry) {
        var line = ""
        if (root.showTimestamp)
            line += entry.timestamp + " "

        switch (entry.type) {
        case "rx":     line += "RX> "; break
        case "tx":     line += "TX> "; break
        case "system": line += "SYS> "; break
        case "error":  line += "ERR> "; break
        default:       line += "> "
        }

        line += (root.hexDisplayMode && entry.hexData !== "") ? entry.hexData : entry.data
        return line
    }

    function copyToClipboard(text) {
        clipHelper.text = text
        clipHelper.selectAll()
        clipHelper.copy()
        clipHelper.text = ""

        // Show feedback in terminal
        var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
        addTerminalEntry(ts, "Copied to clipboard (" + text.split("\n").length + " lines)", "", "system")
    }

    function copySelectedEntries() {
        var lines = []
        for (var i = 0; i < root.terminalEntries.length; i++) {
            if (root.selectedSet.hasOwnProperty(i)) {
                lines.push(buildEntryText(root.terminalEntries[i]))
            }
        }
        if (lines.length > 0)
            copyToClipboard(lines.join("\n"))
    }

    function copyAllEntries() {
        var lines = []
        for (var i = 0; i < terminalModel.count; i++) {
            var entry = terminalModel.get(i)
            lines.push(buildEntryText(entry))
        }
        if (lines.length > 0)
            copyToClipboard(lines.join("\n"))
    }

    // ── Keyword / Whitelist / Blacklist add ─────────────────────
    function addKeyword(text) {
        text = text.trim()
        if (text === "") return
        var color = root.kwPalette[root.kwColorIndex % root.kwPalette.length]
        root.kwColorIndex++
        keywordModel.append({ text: text, color: color })
        kwInput.text = ""
        root.keywordRevision++
    }

    function addWhitelist(text) {
        text = text.trim()
        if (text === "") return
        whitelistModel.append({ text: text })
        wlInput.text = ""
        rebuildFilteredModel()
    }

    function addBlacklist(text) {
        text = text.trim()
        if (text === "") return
        blacklistModel.append({ text: text })
        blInput.text = ""
        rebuildFilteredModel()
    }

    // ── Utilities ───────────────────────────────────────────────
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
