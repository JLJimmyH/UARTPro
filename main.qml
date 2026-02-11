import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs
import Qt.labs.settings 1.0

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
    property int currentTheme: 4
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
        },
        {
            name: "NEON",
            bg: "#0a0a0f", fg: "#ffffff", card: "#12121a", muted: "#1a1a2a",
            mutedFg: "#8888aa", accent: "#00ffff", accentSecondary: "#ff00ff",
            accentTertiary: "#ffff00", border: "#1e1e2e", destructive: "#ff0055"
        },
        {
            name: "FLAT",
            bg: "#ffffff", fg: "#111827", card: "#f3f4f6", muted: "#e5e7eb",
            mutedFg: "#6b7280", accent: "#3b82f6", accentSecondary: "#10b981",
            accentTertiary: "#f59e0b", border: "#e5e7eb", destructive: "#ef4444"
        },
        {
            name: "CLAY",
            bg: "#f4f1fa", fg: "#332f3a", card: "#ffffff", muted: "#ede8f5",
            mutedFg: "#635f69", accent: "#7c3aed", accentSecondary: "#db2777",
            accentTertiary: "#0ea5e9", border: "#ddd6ec", destructive: "#e11d48"
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
        keywordRevision++
    }

    // ── App State ──────────────────────────────────────────────────
    property bool hexDisplayMode: false
    property bool autoScroll: true
    property bool showTimestamp: true
    property bool hexSendMode: false
    property int terminalFontSize: 12
    property real uiScale: 1.0
    property bool showLineNumbers: false
    property bool colorNumbers: true
    onColorNumbersChanged: keywordRevision++
    property int maxBufferLines: 50000
    property int entryIndexOffset: 0
    readonly property var bufferSizeOptions: [10000, 50000, 100000, 500000]
    property string lastClickedRowText: ""
    property string exportMode: "filtered"
    property bool settingsLoaded: false

    // ── Terminal & Keyword State ─────────────────────────────────
    property var terminalEntries: []
    property var selectedSet: ({})
    property int selectionVersion: 0
    property int lastClickedRow: -1
    property int keywordRevision: 0
    property int kwColorIndex: 0
    readonly property var kwPalette: ["#ff3366", "#ffaa00", "#00ff88", "#00d4ff",
                                      "#ff00ff", "#ffff00", "#ff6600", "#aa66ff"]

    // ── Search State ──────────────────────────────────────────────
    property bool searchBarVisible: false
    property string searchQuery: ""
    property bool searchRegex: false
    property int searchCurrentIndex: -1
    property var searchMatches: []
    property bool autoScrollBeforeSearch: true

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

    // ── Keyboard Shortcuts ────────────────────────────────────────
    Shortcut {
        sequence: "Ctrl+L"
        context: Qt.ApplicationShortcut
        onActivated: clearTerminal()
    }
    Shortcut {
        sequence: "Ctrl+C"
        context: Qt.ApplicationShortcut
        onActivated: copySelectedEntries()
    }
    Shortcut {
        sequence: "Ctrl+F"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (!root.searchBarVisible) {
                root.autoScrollBeforeSearch = root.autoScroll
                root.autoScroll = false
            }
            root.searchBarVisible = true
            searchInput.forceActiveFocus()
        }
    }
    Shortcut {
        sequence: "Escape"
        context: Qt.ApplicationShortcut
        onActivated: {
            if (root.searchBarVisible) {
                root.searchBarVisible = false
                root.searchQuery = ""
                root.searchMatches = []
                root.searchCurrentIndex = -1
                root.autoScroll = root.autoScrollBeforeSearch
            }
        }
    }
    Shortcut {
        sequence: "Ctrl+="
        context: Qt.ApplicationShortcut
        onActivated: if (root.terminalFontSize < 24) root.terminalFontSize++
    }
    Shortcut {
        sequence: "Ctrl+-"
        context: Qt.ApplicationShortcut
        onActivated: if (root.terminalFontSize > 8) root.terminalFontSize--
    }
    Shortcut {
        sequence: "Ctrl+0"
        context: Qt.ApplicationShortcut
        onActivated: root.terminalFontSize = 12
    }
    Shortcut {
        sequence: "Ctrl+Shift+="
        context: Qt.ApplicationShortcut
        onActivated: if (root.uiScale < 2.0) root.uiScale = Math.round((root.uiScale + 0.1) * 10) / 10
    }
    Shortcut {
        sequence: "Ctrl+Shift+-"
        context: Qt.ApplicationShortcut
        onActivated: if (root.uiScale > 0.6) root.uiScale = Math.round((root.uiScale - 0.1) * 10) / 10
    }
    Shortcut {
        sequence: "Ctrl+Shift+0"
        context: Qt.ApplicationShortcut
        onActivated: root.uiScale = 1.0
    }

    // ── Scaled Content Wrapper ──────────────────────────────────
    // All visual content is inside this scaled Item.
    // Resize handles stay outside so they remain at actual window edges.
    Item {
        id: contentRoot
        width: root.width / root.uiScale
        height: root.height / root.uiScale
        scale: root.uiScale
        transformOrigin: Item.TopLeft

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
            function onUiScaleChanged() { bgGridCanvas.requestPaint() }
        }
    }

    // Corner accent decorations (HUD style)
    Repeater {
        model: 4
        Item {
            z: 2
            readonly property bool isRight:  index % 2 === 1
            readonly property bool isBottom: index >= 2
            x: isRight  ? contentRoot.width - 30 : 0
            y: isBottom ? contentRoot.height - 30 : 0
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
            enabled: { root.selectionVersion; return Object.keys(root.selectedSet).length > 0 }
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
            enabled: { root.selectionVersion; return Object.keys(root.selectedSet).length > 0 }
            onTriggered: clearSelection()
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: parent.enabled ? root.colorFg : root.colorMutedFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }
        MenuItem {
            text: "  CLEAR TERMINAL"
            onTriggered: clearTerminal()
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: root.colorDestructive
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }

        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: root.colorBorder }
        }

        MenuItem {
            text: "  + HIGHLIGHT THIS"
            enabled: root.lastClickedRowText !== ""
            onTriggered: addKeyword(root.lastClickedRowText)
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: parent.enabled ? "#ffaa00" : root.colorMutedFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }
        MenuItem {
            text: "  + ADD TO WHITELIST"
            enabled: root.lastClickedRowText !== ""
            onTriggered: addWhitelist(root.lastClickedRowText)
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
            text: "  \u2212 ADD TO BLACKLIST"
            enabled: root.lastClickedRowText !== ""
            onTriggered: addBlacklist(root.lastClickedRowText)
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: parent.enabled ? root.colorDestructive : root.colorMutedFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }

        MenuSeparator {
            contentItem: Rectangle { implicitHeight: 1; color: root.colorBorder }
        }

        MenuItem {
            text: "  EXPORT FILTERED..."
            enabled: terminalModel.count > 0
            onTriggered: { root.exportMode = "filtered"; exportSaveDialog.open() }
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: parent.enabled ? root.colorAccentTertiary : root.colorMutedFg
            }
            background: Rectangle {
                color: parent.hovered ? root.colorMuted : "transparent"
            }
        }
        MenuItem {
            text: "  EXPORT ALL..."
            enabled: root.terminalEntries.length > 0
            onTriggered: { root.exportMode = "all"; exportSaveDialog.open() }
            contentItem: Text {
                text: parent.text
                font.family: root.fontMono; font.pixelSize: 11
                font.letterSpacing: 1
                color: parent.enabled ? root.colorAccentTertiary : root.colorMutedFg
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
                    Layout.preferredWidth: 160
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

                // Subtitle — dynamic: shows port info when connected
                Text {
                    text: serialManager.connected
                          ? (portCombo.currentText.split(" - ")[0] + " @ " + baudCombo.currentText)
                          : "// SERIAL TERMINAL INTERFACE"
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 2
                    color: serialManager.connected ? root.colorAccent : root.colorMutedFg
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
                            onCurrentIndexChanged: if (root.settingsLoaded) connectionSettings.lastBaudIndex = currentIndex
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
                            onCurrentIndexChanged: if (root.settingsLoaded) connectionSettings.lastDataBitsIndex = currentIndex
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
                            onCurrentIndexChanged: if (root.settingsLoaded) connectionSettings.lastStopBitsIndex = currentIndex
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
                            onCurrentIndexChanged: if (root.settingsLoaded) connectionSettings.lastParityIndex = currentIndex
                        }

                        Item { height: 4 }

                        // Connect / Disconnect button
                        CyberButton {
                            Layout.fillWidth: true
                            text: serialManager.reconnecting ? "RECONNECTING..."
                                : serialManager.connected ? "DISCONNECT" : "CONNECT"
                            accentColor: serialManager.reconnecting ? "#ffaa00"
                                : serialManager.connected ? root.colorDestructive : root.colorAccent
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder
                            glowing: serialManager.connected || serialManager.reconnecting
                            onClicked: {
                                if (serialManager.reconnecting) {
                                    // Clicking during reconnect = cancel reconnect
                                    serialManager.disconnectPort()
                                } else if (serialManager.connected) {
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
                        CyberCheckBox {
                            text: "LINE NUMBERS"
                            checked: root.showLineNumbers
                            accentColor: root.colorAccentTertiary
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder; mutedFgColor: root.colorMutedFg
                            onCheckedChanged: root.showLineNumbers = checked
                        }
                        CyberCheckBox {
                            text: "NUM COLORS"
                            checked: root.colorNumbers
                            accentColor: root.colorAccentTertiary
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder; mutedFgColor: root.colorMutedFg
                            onCheckedChanged: root.colorNumbers = checked
                        }

                        // Buffer Size
                        Text {
                            text: "BUFFER SIZE"
                            font.family: root.fontMono; font.pixelSize: 10
                            font.letterSpacing: 2; color: root.colorMutedFg
                        }
                        CyberComboBox {
                            id: bufferSizeCombo
                            Layout.fillWidth: true
                            model: root.bufferSizeOptions
                            currentIndex: 1
                            accentColor: root.colorAccentTertiary
                            cardColor: root.colorCard; borderColor: root.colorBorder
                            fgColor: root.colorFg; bgColor: root.colorBg
                            mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
                            onCurrentIndexChanged: root.maxBufferLines = root.bufferSizeOptions[currentIndex]
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
                            text: fileLogger.logging ? "STOP LOGGING" : "LOG TO FILE"
                            accentColor: fileLogger.logging ? root.colorDestructive : root.colorAccent
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder
                            onClicked: {
                                if (fileLogger.logging) {
                                    fileLogger.stopLogging()
                                    var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
                                    addTerminalEntry(ts, "Logging stopped — " + fileLogger.logFilePath, "", "system")
                                } else {
                                    logSaveDialog.selectedFile = "file:///" + fileLogger.generateDefaultPath()
                                    logSaveDialog.open()
                                }
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

                            // Reconnecting indicator
                            Text {
                                visible: serialManager.reconnecting
                                text: "[RECONNECTING]"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                font.bold: true
                                color: "#ffaa00"
                                SequentialAnimation on opacity {
                                    running: serialManager.reconnecting
                                    loops: Animation.Infinite
                                    NumberAnimation { to: 0.3; duration: 600 }
                                    NumberAnimation { to: 1.0; duration: 600 }
                                }
                            }

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

                            Text {
                                visible: { root.selectionVersion; return Object.keys(root.selectedSet).length > 0 }
                                text: { root.selectionVersion; return "[SEL " + Object.keys(root.selectedSet).length + "]" }
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                font.bold: true
                                color: root.colorAccent
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
                                visible: root.terminalFontSize !== 12
                                text: "[" + root.terminalFontSize + "px]"
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                font.bold: true
                                color: root.colorAccentTertiary
                            }

                            Text {
                                visible: root.uiScale !== 1.0
                                text: "[" + Math.round(root.uiScale * 100) + "%]"
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

                    // ── Search Bar ──────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: root.searchBarVisible ? 36 : 0
                        clip: true
                        color: root.colorCard
                        visible: Layout.preferredHeight > 0
                        Behavior on Layout.preferredHeight { NumberAnimation { duration: 150 } }

                        RowLayout {
                            anchors.fill: parent
                            anchors.leftMargin: 12
                            anchors.rightMargin: 12
                            spacing: 6

                            // Search icon
                            Text {
                                text: "\uD83D\uDD0D"
                                font.pixelSize: 13
                                color: root.colorMutedFg
                                Layout.alignment: Qt.AlignVCenter
                            }

                            // Search input
                            TextField {
                                id: searchInput
                                Layout.fillWidth: true
                                Layout.preferredHeight: 28
                                font.family: root.fontMono
                                font.pixelSize: 12
                                color: root.colorAccent
                                placeholderText: "Search..."
                                placeholderTextColor: root.colorMutedFg
                                selectionColor: root.colorAccent
                                selectedTextColor: root.colorBg
                                leftPadding: 6
                                rightPadding: 6

                                background: Rectangle {
                                    color: root.colorBg
                                    border.color: searchInput.activeFocus ? root.colorAccent : root.colorBorder
                                    border.width: 1
                                }

                                onTextChanged: {
                                    root.searchQuery = text
                                    searchDebounce.restart()
                                }

                                Keys.onReturnPressed: function(event) {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        jumpToMatch(-1)
                                    else
                                        jumpToMatch(1)
                                }
                                Keys.onEnterPressed: function(event) {
                                    if (event.modifiers & Qt.ShiftModifier)
                                        jumpToMatch(-1)
                                    else
                                        jumpToMatch(1)
                                }
                            }

                            // Regex toggle
                            Rectangle {
                                Layout.preferredWidth: 28
                                Layout.preferredHeight: 24
                                color: root.searchRegex ? Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.15) : "transparent"
                                border.color: root.searchRegex ? root.colorAccent : root.colorBorder
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: ".*"
                                    font.family: root.fontMono
                                    font.pixelSize: 11
                                    font.bold: root.searchRegex
                                    color: root.searchRegex ? root.colorAccent : root.colorMutedFg
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.searchRegex = !root.searchRegex
                                        if (root.searchQuery !== "")
                                            performSearch()
                                    }
                                }
                            }

                            // Previous match
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                color: prevMa.containsMouse ? Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.15) : "transparent"
                                border.color: root.colorBorder
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u25B2"
                                    font.family: root.fontMono
                                    font.pixelSize: 9
                                    color: root.searchMatches.length > 0 ? root.colorAccent : root.colorMutedFg
                                }

                                MouseArea {
                                    id: prevMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: jumpToMatch(-1)
                                }
                            }

                            // Next match
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                color: nextMa.containsMouse ? Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.15) : "transparent"
                                border.color: root.colorBorder
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u25BC"
                                    font.family: root.fontMono
                                    font.pixelSize: 9
                                    color: root.searchMatches.length > 0 ? root.colorAccent : root.colorMutedFg
                                }

                                MouseArea {
                                    id: nextMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: jumpToMatch(1)
                                }
                            }

                            // Match count
                            Text {
                                text: root.searchMatches.length > 0
                                    ? ((root.searchCurrentIndex + 1) + "/" + root.searchMatches.length)
                                    : (root.searchQuery !== "" ? "0/0" : "")
                                font.family: root.fontMono
                                font.pixelSize: 10
                                font.letterSpacing: 1
                                color: root.searchMatches.length > 0 ? root.colorAccent : root.colorMutedFg
                                Layout.alignment: Qt.AlignVCenter
                                Layout.preferredWidth: 50
                                horizontalAlignment: Text.AlignHCenter
                            }

                            // Close button
                            Rectangle {
                                Layout.preferredWidth: 24
                                Layout.preferredHeight: 24
                                color: searchCloseMa.containsMouse ? Qt.rgba(root.colorDestructive.r, root.colorDestructive.g, root.colorDestructive.b, 0.15) : "transparent"
                                border.color: root.colorBorder
                                border.width: 1
                                Layout.alignment: Qt.AlignVCenter

                                Text {
                                    anchors.centerIn: parent
                                    text: "\u2715"
                                    font.family: root.fontMono
                                    font.pixelSize: 11
                                    color: searchCloseMa.containsMouse ? root.colorDestructive : root.colorMutedFg
                                }

                                MouseArea {
                                    id: searchCloseMa
                                    anchors.fill: parent
                                    hoverEnabled: true
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: {
                                        root.searchBarVisible = false
                                        root.searchQuery = ""
                                        searchInput.text = ""
                                        root.searchMatches = []
                                        root.searchCurrentIndex = -1
                                        root.autoScroll = root.autoScrollBeforeSearch
                                    }
                                }
                            }
                        }

                        // Search debounce timer
                        Timer {
                            id: searchDebounce
                            interval: 150
                            onTriggered: performSearch()
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: root.searchBarVisible ? 1 : 0; color: root.colorBorder }

                    // ── Filter Toolbar ─────────────────────────────
                    Rectangle {
                        Layout.fillWidth: true
                        Layout.preferredHeight: filterToolbarCol.implicitHeight
                        color: root.colorCard
                        visible: Layout.preferredHeight > 0

                        ColumnLayout {
                            id: filterToolbarCol
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.leftMargin: 8
                            anchors.rightMargin: 8
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 4

                            // Input row
                            RowLayout {
                                Layout.fillWidth: true
                                Layout.topMargin: 6
                                spacing: 4

                                CyberComboBox {
                                    id: filterTypeCombo
                                    Layout.preferredWidth: 120
                                    model: ["Highlight", "Whitelist", "Blacklist"]
                                    currentIndex: 0
                                    accentColor: filterTypeCombo.currentIndex === 0 ? "#ffaa00"
                                               : filterTypeCombo.currentIndex === 1 ? root.colorAccent
                                               : root.colorDestructive
                                    cardColor: root.colorCard; borderColor: root.colorBorder
                                    fgColor: root.colorFg; bgColor: root.colorBg
                                    mutedFgColor: root.colorMutedFg; mutedColor: root.colorMuted
                                    font.pixelSize: 11
                                }

                                CyberTextField {
                                    id: filterInput
                                    Layout.fillWidth: true
                                    placeholderText: filterTypeCombo.currentIndex === 0 ? "highlight keyword..."
                                                   : filterTypeCombo.currentIndex === 1 ? "include filter..."
                                                   : "exclude filter..."
                                    accentColor: filterTypeCombo.currentIndex === 0 ? "#ffaa00"
                                               : filterTypeCombo.currentIndex === 1 ? root.colorAccent
                                               : root.colorDestructive
                                    cardColor: root.colorCard; borderColor: root.colorBorder
                                    bgColor: root.colorBg; mutedFgColor: root.colorMutedFg
                                    font.pixelSize: 11

                                    Keys.onReturnPressed: addFilterFromInput()
                                    Keys.onEnterPressed: addFilterFromInput()
                                }

                                CyberButton {
                                    Layout.preferredWidth: 40
                                    text: "+"
                                    accentColor: filterTypeCombo.currentIndex === 0 ? "#ffaa00"
                                               : filterTypeCombo.currentIndex === 1 ? root.colorAccent
                                               : root.colorDestructive
                                    bgColor: root.colorBg; borderMutedColor: root.colorBorder
                                    font.pixelSize: 14
                                    onClicked: addFilterFromInput()
                                }
                            }

                            // Chips area — only visible when there are chips
                            Flow {
                                Layout.fillWidth: true
                                Layout.bottomMargin: 6
                                spacing: 4
                                visible: keywordModel.count > 0 || whitelistModel.count > 0 || blacklistModel.count > 0

                                // Keyword chips
                                Repeater {
                                    model: keywordModel
                                    delegate: Rectangle {
                                        width: kwChipRow.implicitWidth + 16
                                        height: 22
                                        color: Qt.rgba(Qt.color(model.color).r, Qt.color(model.color).g, Qt.color(model.color).b, 0.15)
                                        border.color: model.color
                                        border.width: 1

                                        Row {
                                            id: kwChipRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: model.text
                                                font.family: root.fontMono; font.pixelSize: 10
                                                color: model.color
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: "\u2715"
                                                font.family: root.fontMono; font.pixelSize: 9
                                                font.bold: true
                                                color: root.colorDestructive
                                                opacity: kwChipMa.containsMouse ? 1.0 : 0.5
                                                anchors.verticalCenter: parent.verticalCenter
                                                MouseArea {
                                                    id: kwChipMa
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        root.keywordRevision++
                                                        keywordModel.remove(index)
                                                        settingsSaveTimer.restart()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Whitelist chips
                                Repeater {
                                    model: whitelistModel
                                    delegate: Rectangle {
                                        width: wlChipRow.implicitWidth + 16
                                        height: 22
                                        color: Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.15)
                                        border.color: root.colorAccent
                                        border.width: 1

                                        Row {
                                            id: wlChipRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: "+" + model.text
                                                font.family: root.fontMono; font.pixelSize: 10
                                                color: root.colorAccent
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: "\u2715"
                                                font.family: root.fontMono; font.pixelSize: 9
                                                font.bold: true
                                                color: root.colorDestructive
                                                opacity: wlChipMa.containsMouse ? 1.0 : 0.5
                                                anchors.verticalCenter: parent.verticalCenter
                                                MouseArea {
                                                    id: wlChipMa
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        whitelistModel.remove(index)
                                                        rebuildFilteredModel()
                                                        settingsSaveTimer.restart()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }

                                // Blacklist chips
                                Repeater {
                                    model: blacklistModel
                                    delegate: Rectangle {
                                        width: blChipRow.implicitWidth + 16
                                        height: 22
                                        color: Qt.rgba(root.colorDestructive.r, root.colorDestructive.g, root.colorDestructive.b, 0.15)
                                        border.color: root.colorDestructive
                                        border.width: 1

                                        Row {
                                            id: blChipRow
                                            anchors.centerIn: parent
                                            spacing: 4
                                            Text {
                                                text: "\u2212" + model.text
                                                font.family: root.fontMono; font.pixelSize: 10
                                                color: root.colorDestructive
                                                anchors.verticalCenter: parent.verticalCenter
                                            }
                                            Text {
                                                text: "\u2715"
                                                font.family: root.fontMono; font.pixelSize: 9
                                                font.bold: true
                                                color: root.colorDestructive
                                                opacity: blChipMa.containsMouse ? 1.0 : 0.5
                                                anchors.verticalCenter: parent.verticalCenter
                                                MouseArea {
                                                    id: blChipMa
                                                    anchors.fill: parent
                                                    anchors.margins: -4
                                                    hoverEnabled: true
                                                    cursorShape: Qt.PointingHandCursor
                                                    onClicked: {
                                                        blacklistModel.remove(index)
                                                        rebuildFilteredModel()
                                                        settingsSaveTimer.restart()
                                                    }
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                        }
                    }

                    Rectangle { Layout.fillWidth: true; height: 1; color: root.colorBorder }

                    // Terminal output area
                    Item {
                        Layout.fillWidth: true
                        Layout.fillHeight: true

                        ListModel { id: terminalModel }

                        ListView {
                            id: terminalView
                            anchors.fill: parent
                            anchors.margins: 8
                            model: terminalModel
                            clip: true
                            boundsBehavior: Flickable.StopAtBounds

                            // Auto-scroll detection: disable when user scrolls up, re-enable at bottom
                            property bool atBottom: true
                            onContentYChanged: {
                                if (!moving) return
                                var bottom = (contentHeight - contentY - height) < 30
                                if (bottom && !root.autoScroll) {
                                    root.autoScroll = true
                                } else if (!bottom && root.autoScroll) {
                                    root.autoScroll = false
                                }
                            }

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
                                id: entryDelegate
                                width: terminalView.width
                                height: dataRow.height + 4

                                required property int index
                                required property var timestamp
                                required property var msgText
                                required property var hexData
                                required property var type
                                required property var entryIndex

                                property color resolvedColor: {
                                    switch (String(type)) {
                                    case "rx":     return root.colorAccent
                                    case "tx":     return root.colorAccentTertiary
                                    case "system": return root.colorAccentSecondary
                                    case "error":  return root.colorDestructive
                                    default:       return root.colorFg
                                    }
                                }

                                property bool isSelected: {
                                    root.selectionVersion
                                    return root.selectedSet.hasOwnProperty(entryIndex)
                                }

                                property int searchMatchType: {
                                    // 0 = no match, 1 = other match, 2 = current match
                                    if (!root.searchBarVisible || root.searchMatches.length === 0)
                                        return 0
                                    var idx = entryDelegate.index
                                    if (root.searchCurrentIndex >= 0 && root.searchMatches[root.searchCurrentIndex] === idx)
                                        return 2
                                    for (var i = 0; i < root.searchMatches.length; i++) {
                                        if (root.searchMatches[i] === idx) return 1
                                    }
                                    return 0
                                }

                                // Selection highlight background
                                Rectangle {
                                    anchors.fill: parent
                                    color: entryDelegate.isSelected
                                        ? Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.15)
                                        : "transparent"
                                }

                                // Search match highlight background
                                Rectangle {
                                    anchors.fill: parent
                                    color: entryDelegate.searchMatchType === 2
                                        ? Qt.rgba(1, 0.667, 0, 0.35)   // current match: rgba(255,170,0,0.35)
                                        : entryDelegate.searchMatchType === 1
                                            ? Qt.rgba(1, 0.667, 0, 0.12)  // other matches: rgba(255,170,0,0.12)
                                            : "transparent"
                                }

                                Row {
                                    id: dataRow
                                    x: 4
                                    y: 2
                                    width: entryDelegate.width - 8
                                    spacing: 6

                                    // Line Number
                                    Text {
                                        visible: root.showLineNumbers
                                        text: String(entryDelegate.entryIndex + 1).padStart(4, ' ')
                                        font.family: root.fontMono
                                        font.pixelSize: root.terminalFontSize
                                        color: root.colorMutedFg
                                        opacity: 0.5
                                    }

                                    // Timestamp
                                    Text {
                                        visible: root.showTimestamp
                                        text: entryDelegate.timestamp || ""
                                        font.family: root.fontMono
                                        font.pixelSize: root.terminalFontSize
                                        color: root.colorMutedFg
                                    }

                                    // Prefix + Data (RichText for keyword highlighting)
                                    Text {
                                        text: {
                                            root.keywordRevision  // re-evaluate on keyword change
                                            var prefix = ""
                                            switch (String(entryDelegate.type)) {
                                            case "rx":     prefix = "RX&gt; "; break
                                            case "tx":     prefix = "TX&gt; "; break
                                            case "system": prefix = "SYS&gt; "; break
                                            case "error":  prefix = "ERR&gt; "; break
                                            default:       prefix = "&gt; "
                                            }
                                            var textData = (root.hexDisplayMode && entryDelegate.hexData !== "")
                                                ? entryDelegate.hexData : entryDelegate.msgText
                                            return prefix + highlightText(String(textData))
                                        }
                                        textFormat: Text.RichText
                                        font.family: root.fontMono
                                        font.pixelSize: root.terminalFontSize
                                        color: entryDelegate.resolvedColor
                                        wrapMode: Text.WrapAnywhere
                                        width: parent.width - x
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onClicked: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            root.lastClickedRowText = String(entryDelegate.msgText)
                                            terminalContextMenu.popup()
                                            return
                                        }
                                        if (mouse.modifiers & Qt.ShiftModifier && root.lastClickedRow >= 0) {
                                            selectRange(root.lastClickedRow, entryDelegate.index)
                                        } else if (mouse.modifiers & Qt.ControlModifier) {
                                            toggleSelection(entryDelegate.entryIndex)
                                            root.lastClickedRow = entryDelegate.index
                                        } else {
                                            selectOnly(entryDelegate.entryIndex)
                                            root.lastClickedRow = entryDelegate.index
                                        }
                                    }
                                    onWheel: function(wheel) {
                                        if ((wheel.modifiers & Qt.ControlModifier) && (wheel.modifiers & Qt.ShiftModifier)) {
                                            if (wheel.angleDelta.y > 0 && root.uiScale < 2.0)
                                                root.uiScale = Math.round((root.uiScale + 0.1) * 10) / 10
                                            else if (wheel.angleDelta.y < 0 && root.uiScale > 0.6)
                                                root.uiScale = Math.round((root.uiScale - 0.1) * 10) / 10
                                            wheel.accepted = true
                                        } else if (wheel.modifiers & Qt.ControlModifier) {
                                            if (wheel.angleDelta.y > 0 && root.terminalFontSize < 24)
                                                root.terminalFontSize++
                                            else if (wheel.angleDelta.y < 0 && root.terminalFontSize > 8)
                                                root.terminalFontSize--
                                            wheel.accepted = true
                                        } else {
                                            wheel.accepted = false
                                        }
                                    }
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

                        // Auto-scroll paused overlay
                        Rectangle {
                            anchors.bottom: parent.bottom
                            anchors.left: parent.left
                            anchors.right: parent.right
                            anchors.margins: 8
                            height: 32
                            z: 5
                            visible: !root.autoScroll && terminalModel.count > 0
                            color: Qt.rgba(root.colorCard.r, root.colorCard.g, root.colorCard.b, 0.92)
                            border.color: root.colorAccent
                            border.width: 1

                            opacity: !root.autoScroll && terminalModel.count > 0 ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 150 } }

                            Row {
                                anchors.centerIn: parent
                                spacing: 12

                                Text {
                                    text: "\u23F8 AUTO-SCROLL PAUSED"
                                    font.family: root.fontMono
                                    font.pixelSize: 10
                                    font.letterSpacing: 1
                                    color: root.colorAccentTertiary
                                    anchors.verticalCenter: parent.verticalCenter
                                }

                                Rectangle {
                                    width: jumpText.width + 16
                                    height: 22
                                    color: jumpMa.containsMouse ? root.colorAccent : "transparent"
                                    border.color: root.colorAccent
                                    border.width: 1
                                    anchors.verticalCenter: parent.verticalCenter

                                    Text {
                                        id: jumpText
                                        anchors.centerIn: parent
                                        text: "\u2193 JUMP TO LATEST"
                                        font.family: root.fontMono
                                        font.pixelSize: 10
                                        font.letterSpacing: 1
                                        font.bold: true
                                        color: jumpMa.containsMouse ? root.colorBg : root.colorAccent
                                    }

                                    MouseArea {
                                        id: jumpMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.autoScroll = true
                                            terminalView.positionViewAtEnd()
                                        }
                                    }
                                }
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
                                onCurrentIndexChanged: if (root.settingsLoaded) connectionSettings.lastLineEndingIndex = currentIndex
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

                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: root.colorBorder }

                // Buffer usage
                Text {
                    text: "BUF: " + root.terminalEntries.length + "/" + root.maxBufferLines
                    font.family: root.fontMono
                    font.pixelSize: 10
                    font.letterSpacing: 1
                    color: (root.terminalEntries.length / root.maxBufferLines > 0.9)
                           ? "#ffaa00" : root.colorMutedFg
                }

                // REC indicator (visible when logging)
                Rectangle { width: 1; Layout.fillHeight: true; Layout.topMargin: 6; Layout.bottomMargin: 6; color: root.colorBorder; visible: fileLogger.logging }

                Row {
                    visible: fileLogger.logging
                    spacing: 4
                    Layout.alignment: Qt.AlignVCenter

                    Rectangle {
                        id: recDot
                        width: 6; height: 6; radius: 3
                        color: root.colorDestructive
                        anchors.verticalCenter: parent.verticalCenter

                        SequentialAnimation on opacity {
                            running: fileLogger.logging
                            loops: Animation.Infinite
                            NumberAnimation { to: 0.3; duration: 600 }
                            NumberAnimation { to: 1.0; duration: 600 }
                        }
                    }

                    Text {
                        text: "REC " + formatBytes(fileLogger.logFileSize)
                        font.family: root.fontMono
                        font.pixelSize: 10
                        font.letterSpacing: 1
                        font.bold: true
                        color: root.colorDestructive
                    }
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
            function onUiScaleChanged() { scanlineCanvas.requestPaint() }
        }
    }

    } // contentRoot

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
    // FILE DIALOGS
    // ══════════════════════════════════════════════════════════════
    FileDialog {
        id: logSaveDialog
        title: "Save Log File"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Log files (*.log)", "Text files (*.txt)", "All files (*)"]
        onAccepted: {
            if (fileLogger.startLogging(selectedFile.toString())) {
                var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
                addTerminalEntry(ts, "Logging started — " + fileLogger.logFilePath, "", "system")
            } else {
                var ts2 = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
                addTerminalEntry(ts2, "Failed to start logging", "", "error")
            }
        }
    }

    FileDialog {
        id: exportSaveDialog
        title: "Export Data"
        fileMode: FileDialog.SaveFile
        nameFilters: ["Log files (*.log)", "CSV files (*.csv)", "All files (*)"]
        onAccepted: {
            var path = selectedFile.toString()
            var entries = collectExportEntries()
            var isCsv = path.toLowerCase().endsWith(".csv")
            var ok = isCsv ? fileLogger.exportCsv(path, entries)
                           : fileLogger.exportPlainText(path, entries)
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            if (ok)
                addTerminalEntry(ts, "Exported " + entries.length + " entries to file (" + (isCsv ? "CSV" : "TXT") + ")", "", "system")
            else
                addTerminalEntry(ts, "Export failed", "", "error")
        }
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
            } else if (!serialManager.reconnecting) {
                addTerminalEntry(ts, "Connection closed", "", "system")
            }
        }

        function onConnectionLost() {
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            addTerminalEntry(ts, "Device disconnected — auto-reconnecting...", "", "error")
        }

        function onReconnected() {
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            addTerminalEntry(ts, "Reconnected successfully", "", "system")
        }

        function onDataReceived(timestamp, asciiData, hexData) {
            addTerminalEntry(timestamp, asciiData, hexData, "rx")
        }

        function onErrorOccurred(error) {
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            if (!serialManager.reconnecting)
                addTerminalEntry(ts, error, "", "error")
        }
    }

    // ══════════════════════════════════════════════════════════════
    // HELPER FUNCTIONS
    // ══════════════════════════════════════════════════════════════

    // ── Entry & Filter ──────────────────────────────────────────
    function addTerminalEntry(timestamp, data, hexData, type) {
        var entry = {
            timestamp: timestamp,
            msgText: data,
            hexData: hexData || "",
            type: type,
            entryIndex: root.entryIndexOffset + root.terminalEntries.length
        }

        // Log to file if active
        if (fileLogger.logging)
            fileLogger.logEntry(timestamp, type, data, hexData || "")

        var entries = root.terminalEntries
        entries.push(entry)

        // Buffer limit: trim oldest 10% when exceeding max
        if (entries.length > root.maxBufferLines) {
            var removeCount = Math.floor(root.maxBufferLines * 0.1)
            var removedMaxIndex = entries[removeCount - 1].entryIndex

            entries.splice(0, removeCount)
            root.entryIndexOffset += removeCount

            // Sync terminalModel: remove entries at front with entryIndex <= threshold
            var modelRemoveCount = 0
            for (var m = 0; m < terminalModel.count; m++) {
                if (terminalModel.get(m).entryIndex <= removedMaxIndex)
                    modelRemoveCount++
                else
                    break
            }
            if (modelRemoveCount > 0)
                terminalModel.remove(0, modelRemoveCount)

            // Sync selectedSet
            var newSel = {}
            var keys = Object.keys(root.selectedSet)
            for (var k = 0; k < keys.length; k++) {
                if (parseInt(keys[k]) > removedMaxIndex)
                    newSel[keys[k]] = true
            }
            root.selectedSet = newSel
            root.selectionVersion++

            // Invalidate search matches
            if (root.searchMatches.length > 0) {
                root.searchMatches = []
                root.searchCurrentIndex = -1
            }
        }

        root.terminalEntries = entries

        if (passesFilter(entry)) {
            terminalModel.append(entry)
            if (root.autoScroll)
                terminalView.positionViewAtEnd()
        }
    }

    function passesFilter(entry) {
        // system and error messages always pass
        if (entry.type === "system" || entry.type === "error")
            return true

        var text = entry.msgText.toLowerCase()

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

    // ── Search ────────────────────────────────────────────────
    function performSearch() {
        var q = root.searchQuery
        if (q === "") {
            root.searchMatches = []
            root.searchCurrentIndex = -1
            return
        }

        var matches = []
        var re
        try {
            if (root.searchRegex)
                re = new RegExp(q, "i")
            else
                re = new RegExp(escapeRegex(q), "i")
        } catch (e) {
            root.searchMatches = []
            root.searchCurrentIndex = -1
            return
        }

        for (var i = 0; i < terminalModel.count; i++) {
            var entry = terminalModel.get(i)
            var text = (root.hexDisplayMode && entry.hexData !== "") ? entry.hexData : entry.msgText
            if (re.test(String(text))) {
                matches.push(i)
            }
        }

        root.searchMatches = matches
        if (matches.length > 0) {
            root.searchCurrentIndex = 0
            terminalView.positionViewAtIndex(matches[0], ListView.Center)
        } else {
            root.searchCurrentIndex = -1
        }
    }

    function jumpToMatch(direction) {
        if (root.searchMatches.length === 0) return

        var idx = root.searchCurrentIndex + direction
        if (idx >= root.searchMatches.length) idx = 0
        if (idx < 0) idx = root.searchMatches.length - 1

        root.searchCurrentIndex = idx
        terminalView.positionViewAtIndex(root.searchMatches[idx], ListView.Center)
    }

    // ── Keyword Highlighting ────────────────────────────────────
    function escapeHtml(str) {
        return str.replace(/&/g, "&amp;").replace(/</g, "&lt;").replace(/>/g, "&gt;")
    }

    function escapeRegex(str) {
        return str.replace(/[.*+?^${}()|[\]\\]/g, "\\$&")
    }

    function highlightText(raw) {
        var html = escapeHtml(raw)

        // Step 1: Keyword highlighting
        for (var i = 0; i < keywordModel.count; i++) {
            var kw = keywordModel.get(i)
            var escaped = escapeRegex(escapeHtml(kw.text))
            var re = new RegExp("(" + escaped + ")", "gi")
            html = html.replace(re, "<span style='background-color:" + kw.color + ";color:" + root.colorBg + ";font-weight:bold;'>$1</span>")
        }

        // Step 2: Color numbers outside HTML tags (won't touch tag attributes)
        if (root.colorNumbers) {
            var numColor = String(root.colorAccentTertiary)
            html = html.replace(/(<[^>]+>)|(\b(?:0x[0-9a-fA-F]+|\d+\.?\d*)\b)/g, function(match, tag, num) {
                if (tag) return tag
                return "<span style='color:" + numColor + ";'>" + num + "</span>"
            })
        }

        return html
    }

    // ── Selection ───────────────────────────────────────────────
    function selectOnly(entryIdx) {
        var s = {}
        s[entryIdx] = true
        root.selectedSet = s
        root.selectionVersion++
    }

    function toggleSelection(entryIdx) {
        var s = root.selectedSet
        if (s.hasOwnProperty(entryIdx))
            delete s[entryIdx]
        else
            s[entryIdx] = true
        root.selectedSet = s
        root.selectionVersion++
    }

    function selectRange(fromRow, toRow) {
        var lo = Math.min(fromRow, toRow)
        var hi = Math.max(fromRow, toRow)
        var s = root.selectedSet
        for (var i = lo; i <= hi; i++) {
            var entry = terminalModel.get(i)
            if (entry) s[entry.entryIndex] = true
        }
        root.selectedSet = s
        root.selectionVersion++
    }

    function clearSelection() {
        root.selectedSet = {}
        root.selectionVersion++
        root.lastClickedRow = -1
    }

    function selectAllEntries() {
        var s = {}
        for (var i = 0; i < terminalModel.count; i++) {
            s[terminalModel.get(i).entryIndex] = true
        }
        root.selectedSet = s
        root.selectionVersion++
    }

    function clearTerminal() {
        terminalModel.clear()
        root.terminalEntries = []
        root.entryIndexOffset = 0
        clearSelection()
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

        line += (root.hexDisplayMode && entry.hexData !== "") ? entry.hexData : entry.msgText
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
    function addFilterFromInput() {
        var text = filterInput.text.trim()
        if (text === "") return
        if (filterTypeCombo.currentIndex === 0)
            addKeyword(text)
        else if (filterTypeCombo.currentIndex === 1)
            addWhitelist(text)
        else
            addBlacklist(text)
        filterInput.text = ""
    }

    function addKeyword(text) {
        text = text.trim()
        if (text === "") return
        var color = root.kwPalette[root.kwColorIndex % root.kwPalette.length]
        root.kwColorIndex++
        keywordModel.append({ text: text, color: color })
        root.keywordRevision++
        settingsSaveTimer.restart()
    }

    function addWhitelist(text) {
        text = text.trim()
        if (text === "") return
        whitelistModel.append({ text: text })
        rebuildFilteredModel()
        settingsSaveTimer.restart()
    }

    function addBlacklist(text) {
        text = text.trim()
        if (text === "") return
        blacklistModel.append({ text: text })
        rebuildFilteredModel()
        settingsSaveTimer.restart()
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

    function collectExportEntries() {
        var result = []
        if (root.exportMode === "filtered") {
            for (var i = 0; i < terminalModel.count; i++) {
                var item = terminalModel.get(i)
                result.push({ timestamp: item.timestamp, type: item.type,
                              msgText: item.msgText, hexData: item.hexData })
            }
        } else {
            for (var j = 0; j < root.terminalEntries.length; j++) {
                var e = root.terminalEntries[j]
                result.push({ timestamp: e.timestamp, type: e.type,
                              msgText: e.msgText, hexData: e.hexData })
            }
        }
        return result
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

    // ══════════════════════════════════════════════════════════════
    // SETTINGS PERSISTENCE (CH-14)
    // ══════════════════════════════════════════════════════════════
    Settings {
        id: generalSettings
        category: "General"
        property alias theme: root.currentTheme
        property alias fontSize: root.terminalFontSize
        property alias showTimestamp: root.showTimestamp
        property alias hexDisplayMode: root.hexDisplayMode
        property alias showLineNumbers: root.showLineNumbers
        property alias colorNumbers: root.colorNumbers
        property alias uiScale: root.uiScale
        property alias hexSendMode: root.hexSendMode
        property alias maxBufferLines: root.maxBufferLines
    }

    Settings {
        id: filterSettings
        category: "Filters"
        property string keywordsJson: "[]"
        property string whitelistJson: "[]"
        property string blacklistJson: "[]"
    }

    Settings {
        id: connectionSettings
        category: "Connection"
        property int lastBaudIndex: 4
        property int lastDataBitsIndex: 0
        property int lastStopBitsIndex: 0
        property int lastParityIndex: 0
        property int lastLineEndingIndex: 0
    }

    function serializeListModel(model) {
        var arr = []
        for (var i = 0; i < model.count; i++) {
            var item = model.get(i)
            arr.push({ text: item.text, color: item.color || "" })
        }
        return JSON.stringify(arr)
    }

    function deserializeToListModel(model, jsonStr) {
        model.clear()
        try {
            var arr = JSON.parse(jsonStr)
            for (var i = 0; i < arr.length; i++)
                model.append(arr[i])
        } catch(e) { /* ignore bad JSON */ }
    }

    Timer {
        id: settingsSaveTimer
        interval: 500
        onTriggered: {
            if (!root.settingsLoaded) return
            filterSettings.keywordsJson = serializeListModel(keywordModel)
            filterSettings.whitelistJson = serializeListModel(whitelistModel)
            filterSettings.blacklistJson = serializeListModel(blacklistModel)
        }
    }

    // Boot sequence on startup
    Component.onCompleted: {
        // Restore connection combo indices
        baudCombo.currentIndex = connectionSettings.lastBaudIndex
        dataBitsCombo.currentIndex = connectionSettings.lastDataBitsIndex
        stopBitsCombo.currentIndex = connectionSettings.lastStopBitsIndex
        parityCombo.currentIndex = connectionSettings.lastParityIndex
        lineEndingCombo.currentIndex = connectionSettings.lastLineEndingIndex

        // Restore buffer size combo
        var bufIdx = root.bufferSizeOptions.indexOf(root.maxBufferLines)
        if (bufIdx >= 0) bufferSizeCombo.currentIndex = bufIdx

        // Apply saved theme
        applyTheme(root.currentTheme)

        // Restore filter models
        deserializeToListModel(keywordModel, filterSettings.keywordsJson)
        deserializeToListModel(whitelistModel, filterSettings.whitelistJson)
        deserializeToListModel(blacklistModel, filterSettings.blacklistJson)

        // Rebuild filtered view if filters are active
        if (whitelistModel.count > 0 || blacklistModel.count > 0)
            rebuildFilteredModel()

        root.settingsLoaded = true

        var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
        addTerminalEntry(ts, "UART PRO v0.1 // SERIAL TERMINAL INTERFACE", "", "system")
        addTerminalEntry(ts, "System initialized. Ready for connection.", "", "system")
        addTerminalEntry(ts, "Select a port and click CONNECT to begin.", "", "system")
        serialManager.refreshPorts()
    }
}
