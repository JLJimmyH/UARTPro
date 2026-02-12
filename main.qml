import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Dialogs

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
        },
        {
            name: "WEB3",
            bg: "#030304", fg: "#ffffff", card: "#0f1115", muted: "#161b22",
            mutedFg: "#94a3b8", accent: "#f7931a", accentSecondary: "#ea580c",
            accentTertiary: "#ffd600", border: "#1e293b", destructive: "#dc2626"
        },
        {
            name: "MONOKAI",
            bg: "#272822", fg: "#f8f8f2", card: "#1e1f1c", muted: "#3e3d32",
            mutedFg: "#75715e", accent: "#a6e22e", accentSecondary: "#fd971f",
            accentTertiary: "#66d9ef", border: "#3e3d32", destructive: "#f92672"
        },
        {
            name: "DUSK",
            bg: "#282c34", fg: "#abb2bf", card: "#21252b", muted: "#2c313a",
            mutedFg: "#5c6370", accent: "#61afef", accentSecondary: "#c678dd",
            accentTertiary: "#56b6c2", border: "#3e4452", destructive: "#e06c75"
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
    property bool showPrefix: true
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
    property bool leftPanelCollapsed: false

    // ── Config sync handlers ─────────────────────────────────────
    onCurrentThemeChanged: if (configManager) configManager.currentTheme = currentTheme
    onTerminalFontSizeChanged: if (configManager) configManager.terminalFontSize = terminalFontSize
    onUiScaleChanged: if (configManager) configManager.uiScale = uiScale

    // ── Terminal & Keyword State ─────────────────────────────────
    property var terminalEntries: []
    property var selectedSet: ({})
    property int selectionVersion: 0
    property int lastClickedRow: -1
    property int activeEditRow: -1      // entryIndex of the row in text-select mode
    property int _selStart: -1          // character selection start position
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
    ListModel { id: whitelistModel; onCountChanged: rebuildFilteredModel() }
    ListModel { id: blacklistModel; onCountChanged: rebuildFilteredModel() }

    // Hidden TextEdit for clipboard access
    TextEdit { id: clipHelper; visible: false }

    // ── Config drag-and-drop + reload ─────────────────────────────
    Connections {
        target: configManager
        function onConfigLoaded() {
            loadConfigToUI()
            var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
            addTerminalEntry(ts, "Config loaded: " + configManager.configFilePath, "", "system")
        }
    }

    DropArea {
        id: configDropArea
        anchors.fill: parent
        z: 9999
        keys: ["text/uri-list"]
        property bool dragActive: false

        onEntered: function(drag) {
            if (drag.hasUrls) {
                for (var i = 0; i < drag.urls.length; i++) {
                    if (drag.urls[i].toString().toLowerCase().endsWith(".json")) {
                        drag.accepted = true
                        dragActive = true
                        return
                    }
                }
            }
            drag.accepted = false
        }
        onExited: dragActive = false
        onDropped: function(drop) {
            dragActive = false
            for (var i = 0; i < drop.urls.length; i++) {
                var url = drop.urls[i].toString()
                if (url.toLowerCase().endsWith(".json")) {
                    configManager.loadFromFile(url)
                    return
                }
            }
        }

        Rectangle {
            anchors.fill: parent
            visible: configDropArea.dragActive
            color: Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.1)
            border.color: root.colorAccent
            border.width: 2
            z: 10000

            Column {
                anchors.centerIn: parent
                spacing: 8
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "\u2913"
                    font.pixelSize: 48
                    color: root.colorAccent
                }
                Text {
                    anchors.horizontalCenter: parent.horizontalCenter
                    text: "DROP JSON CONFIG FILE"
                    font.family: root.fontMono
                    font.pixelSize: 14
                    font.letterSpacing: 2
                    font.bold: true
                    color: root.colorAccent
                }
            }
        }
    }

    // ── Keyboard Shortcuts ────────────────────────────────────────
    Shortcut {
        sequence: "Ctrl+L"
        context: Qt.ApplicationShortcut
        onActivated: clearTerminal()
    }
    Shortcut {
        sequence: "Ctrl+C"
        context: Qt.ApplicationShortcut
        onActivated: copySelectedOrInlineText()
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
    Shortcut {
        sequence: "Space"
        context: Qt.ApplicationShortcut
        onActivated: {
            // Don't trigger when a text input has focus
            if (sendInput.activeFocus || searchInput.activeFocus || filterInput.activeFocus)
                return
            toggleConnection()
        }
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
            onTriggered: copySelectedOrInlineText()
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
                    id: themeSwitcherBtn
                    width: themeLabel.width + themeSwatches.width + 24
                    height: 26
                    color: themeMa.containsMouse || themePopup.visible ? root.colorMuted : "transparent"
                    border.color: themeMa.containsMouse || themePopup.visible ? root.colorAccent : root.colorBorder
                    border.width: 1
                    Behavior on border.color { ColorAnimation { duration: 150 } }
                    Behavior on color { ColorAnimation { duration: 150 } }

                    Row {
                        anchors.centerIn: parent
                        spacing: 6
                        Text {
                            id: themeLabel
                            anchors.verticalCenter: parent.verticalCenter
                            text: root.themes[root.currentTheme].name
                            font.family: root.fontMono
                            font.pixelSize: 10
                            font.letterSpacing: 1
                            font.bold: true
                            color: themeMa.containsMouse || themePopup.visible ? root.colorAccent : root.colorMutedFg
                            Behavior on color { ColorAnimation { duration: 150 } }
                        }
                        Row {
                            id: themeSwatches
                            anchors.verticalCenter: parent.verticalCenter
                            spacing: 2
                            Repeater {
                                model: [
                                    root.themes[root.currentTheme].accent,
                                    root.themes[root.currentTheme].accentSecondary,
                                    root.themes[root.currentTheme].accentTertiary
                                ]
                                Rectangle { width: 8; height: 8; color: modelData }
                            }
                        }
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            text: themePopup.visible ? "\u25B2" : "\u25BC"
                            font.family: root.fontMono
                            font.pixelSize: 7
                            color: root.colorMutedFg
                        }
                    }
                    MouseArea {
                        id: themeMa
                        anchors.fill: parent
                        hoverEnabled: true
                        cursorShape: Qt.PointingHandCursor
                        onClicked: themePopup.visible ? themePopup.close() : themePopup.open()
                    }

                    Popup {
                        id: themePopup
                        y: themeSwitcherBtn.height + 2
                        width: 200
                        padding: 4
                        closePolicy: Popup.CloseOnEscape | Popup.CloseOnPressOutsideParent

                        background: Rectangle {
                            color: root.colorCard
                            border.color: root.colorAccent
                            border.width: 1
                        }

                        contentItem: Column {
                            spacing: 2
                            Repeater {
                                model: root.themes.length
                                Rectangle {
                                    width: 192
                                    height: 28
                                    color: themeItemMa.containsMouse ? root.colorMuted
                                           : (root.currentTheme === index ? Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.1) : "transparent")
                                    border.color: root.currentTheme === index ? root.colorAccent : "transparent"
                                    border.width: root.currentTheme === index ? 1 : 0

                                    Row {
                                        anchors.fill: parent
                                        anchors.leftMargin: 8
                                        anchors.rightMargin: 8
                                        spacing: 8

                                        Text {
                                            anchors.verticalCenter: parent.verticalCenter
                                            width: 70
                                            text: root.themes[index].name
                                            font.family: root.fontMono
                                            font.pixelSize: 10
                                            font.letterSpacing: 1
                                            font.bold: root.currentTheme === index
                                            color: root.currentTheme === index ? root.colorAccent : root.colorFg
                                        }

                                        // Color swatch strip
                                        Row {
                                            anchors.verticalCenter: parent.verticalCenter
                                            spacing: 3
                                            // bg swatch
                                            Rectangle {
                                                width: 14; height: 14
                                                color: root.themes[index].bg
                                                border.color: root.themes[index].border
                                                border.width: 1
                                            }
                                            // accent
                                            Rectangle {
                                                width: 14; height: 14
                                                color: root.themes[index].accent
                                            }
                                            // accentSecondary
                                            Rectangle {
                                                width: 14; height: 14
                                                color: root.themes[index].accentSecondary
                                            }
                                            // accentTertiary
                                            Rectangle {
                                                width: 14; height: 14
                                                color: root.themes[index].accentTertiary
                                            }
                                            // destructive
                                            Rectangle {
                                                width: 14; height: 14
                                                color: root.themes[index].destructive
                                            }
                                        }
                                    }

                                    MouseArea {
                                        id: themeItemMa
                                        anchors.fill: parent
                                        hoverEnabled: true
                                        cursorShape: Qt.PointingHandCursor
                                        onClicked: {
                                            root.applyTheme(index)
                                            themePopup.close()
                                        }
                                    }
                                }
                            }
                        }
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
                id: leftPanel
                Layout.preferredWidth: root.leftPanelCollapsed ? 0 : 280
                Layout.fillHeight: true
                color: root.colorCard
                border.color: root.colorBorder
                border.width: root.leftPanelCollapsed ? 0 : 1
                clip: true
                visible: Layout.preferredWidth > 0

                Behavior on Layout.preferredWidth {
                    NumberAnimation { duration: 200; easing.type: Easing.OutCubic }
                }

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

                        // Hidden combos — keep IDs for compatibility
                        CyberComboBox { id: dataBitsCombo; visible: false; model: root.dataBitsList; currentIndex: 0 }
                        CyberComboBox { id: stopBitsCombo; visible: false; model: root.stopBitsList; currentIndex: 0 }
                        CyberComboBox { id: parityCombo; visible: false; model: root.parityList; currentIndex: 0 }

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
                            onClicked: toggleConnection()
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
                            text: "PREFIX"
                            checked: root.showPrefix
                            accentColor: root.colorAccentTertiary
                            bgColor: root.colorBg; borderMutedColor: root.colorBorder; mutedFgColor: root.colorMutedFg
                            onCheckedChanged: root.showPrefix = checked
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

                            // Toggle left panel button
                            Text {
                                text: root.leftPanelCollapsed ? "\u25b6" : "\u25c0"
                                font.pixelSize: 12
                                color: root.colorMutedFg
                                MouseArea {
                                    anchors.fill: parent
                                    cursorShape: Qt.PointingHandCursor
                                    onClicked: root.leftPanelCollapsed = !root.leftPanelCollapsed
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
                                                        syncKeywordsToConfig()
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
                                                    onClicked: { whitelistModel.remove(index); syncWhitelistToConfig() }
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
                                                    onClicked: { blacklistModel.remove(index); syncBlacklistToConfig() }
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
                            interactive: false   // disable mouse-drag scrolling; wheel still works via MouseArea
                            boundsBehavior: Flickable.StopAtBounds

                            // Auto-scroll rules:
                            //   1. Scroll to bottom → enable auto-scroll
                            //   2. Any upward scroll → disable auto-scroll

                            function isAtBottom() {
                                if (terminalModel.count === 0) return true
                                var lastItem = itemAtIndex(terminalModel.count - 1)
                                if (!lastItem) return false
                                return (lastItem.y + lastItem.height) <= (contentY + height + 2)
                            }

                            // Re-enable auto-scroll when reaching bottom
                            onContentYChanged: {
                                if (!root.autoScroll && isAtBottom())
                                    root.autoScroll = true
                            }

                            // Re-position to bottom after scale/font changes when auto-scroll is active
                            Timer {
                                id: scaleRepositionTimer
                                interval: 80
                                onTriggered: {
                                    if (root.autoScroll)
                                        terminalView.positionViewAtEnd()
                                }
                            }
                            Connections {
                                target: root
                                function onUiScaleChanged()          { scaleRepositionTimer.restart() }
                                function onTerminalFontSizeChanged() { scaleRepositionTimer.restart() }
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
                                        id: displayText
                                        visible: root.activeEditRow !== entryDelegate.entryIndex
                                        text: {
                                            root.keywordRevision  // re-evaluate on keyword change
                                            var prefix = ""
                                            if (root.showPrefix) {
                                                switch (String(entryDelegate.type)) {
                                                case "rx":     prefix = "RX&gt; "; break
                                                case "tx":     prefix = "TX&gt; "; break
                                                case "system": prefix = "SYS&gt; "; break
                                                case "error":  prefix = "ERR&gt; "; break
                                                default:       prefix = "&gt; "
                                                }
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

                                    // Selectable TextEdit (plain text, shown on click for char-level selection)
                                    TextEdit {
                                        id: editText
                                        objectName: "editText"
                                        visible: root.activeEditRow === entryDelegate.entryIndex
                                        text: {
                                            var prefix = ""
                                            if (root.showPrefix) {
                                                switch (String(entryDelegate.type)) {
                                                case "rx":     prefix = "RX> "; break
                                                case "tx":     prefix = "TX> "; break
                                                case "system": prefix = "SYS> "; break
                                                case "error":  prefix = "ERR> "; break
                                                default:       prefix = "> "
                                                }
                                            }
                                            var textData = (root.hexDisplayMode && entryDelegate.hexData !== "")
                                                ? entryDelegate.hexData : entryDelegate.msgText
                                            return prefix + String(textData)
                                        }
                                        readOnly: true
                                        selectByMouse: false   // we control selection programmatically
                                        font.family: root.fontMono
                                        font.pixelSize: root.terminalFontSize
                                        color: entryDelegate.resolvedColor
                                        selectedTextColor: root.colorBg
                                        selectionColor: Qt.rgba(root.colorAccent.r, root.colorAccent.g, root.colorAccent.b, 0.6)
                                        wrapMode: TextEdit.WrapAnywhere
                                        width: parent.width - x
                                    }
                                }

                                MouseArea {
                                    anchors.fill: parent
                                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                                    onPressed: function(mouse) {
                                        if (mouse.button === Qt.RightButton) {
                                            root.lastClickedRowText = String(entryDelegate.msgText)
                                            terminalContextMenu.popup()
                                            mouse.accepted = true
                                            return
                                        }
                                        // Ctrl / Shift clicks → line-level selection (original behaviour)
                                        if (mouse.modifiers & Qt.ShiftModifier && root.lastClickedRow >= 0) {
                                            root.activeEditRow = -1
                                            selectRange(root.lastClickedRow, entryDelegate.index)
                                            mouse.accepted = true
                                            return
                                        }
                                        if (mouse.modifiers & Qt.ControlModifier) {
                                            root.activeEditRow = -1
                                            toggleSelection(entryDelegate.entryIndex)
                                            root.lastClickedRow = entryDelegate.index
                                            mouse.accepted = true
                                            return
                                        }
                                        // Plain left click → activate char-level selection on this row
                                        root.activeEditRow = entryDelegate.entryIndex
                                        root.autoScroll = false
                                        selectOnly(entryDelegate.entryIndex)
                                        root.lastClickedRow = entryDelegate.index
                                        // Calculate start position for drag selection
                                        var localX = mouse.x - dataRow.x - editText.x
                                        var localY = mouse.y - dataRow.y - editText.y
                                        root._selStart = editText.positionAt(localX, localY)
                                        editText.cursorPosition = root._selStart
                                        editText.select(root._selStart, root._selStart) // clear previous selection
                                    }
                                    onPositionChanged: function(mouse) {
                                        // Drag → update character selection
                                        if (pressed && root.activeEditRow === entryDelegate.entryIndex && root._selStart >= 0) {
                                            var localX = mouse.x - dataRow.x - editText.x
                                            var localY = mouse.y - dataRow.y - editText.y
                                            var pos = editText.positionAt(localX, localY)
                                            editText.select(root._selStart, pos)
                                        }
                                    }
                                    onReleased: function(mouse) {
                                        root._selStart = -1
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
                                            // Manual scroll (interactive is false)
                                            var step = 60
                                            terminalView.contentY = Math.max(0,
                                                Math.min(terminalView.contentHeight - terminalView.height,
                                                    terminalView.contentY - (wheel.angleDelta.y > 0 ? step : -step)))
                                            if (wheel.angleDelta.y > 0)
                                                root.autoScroll = false
                                            wheel.accepted = true
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
        root.activeEditRow = -1
    }

    function selectAllEntries() {
        var s = {}
        for (var i = 0; i < terminalModel.count; i++) {
            s[terminalModel.get(i).entryIndex] = true
        }
        root.selectedSet = s
        root.selectionVersion++
    }

    function toggleConnection() {
        if (serialManager.reconnecting) {
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
                8, 1, 0
            )
            if (!ok) {
                addTerminalEntry(
                    Qt.formatDateTime(new Date(), "HH:mm:ss.zzz"),
                    "Failed to open port", "", "error"
                )
            }
        }
    }

    function clearTerminal() {
        terminalModel.clear()
        root.terminalEntries = []
        root.entryIndexOffset = 0
        clearSelection()
    }

    function copySelectedOrInlineText() {
        // If a TextEdit has selected text, copy that (partial line)
        if (root.activeEditRow >= 0) {
            var item = terminalView.itemAtIndex !== undefined
                ? terminalView.itemAtIndex(getModelIndexForEntry(root.activeEditRow))
                : null
            if (item) {
                var et = item.children ? findEditText(item) : null
                if (et && et.selectedText.length > 0) {
                    copyToClipboardInline(et.selectedText)
                    return
                }
            }
        }
        // Fallback: copy whole selected lines
        copySelectedEntries()
    }

    function findEditText(item) {
        // Walk children to find the editText TextEdit
        for (var i = 0; i < item.children.length; i++) {
            var child = item.children[i]
            if (child.objectName === "editText") return child
            // Check grandchildren (inside Row)
            if (child.children) {
                for (var j = 0; j < child.children.length; j++) {
                    if (child.children[j].objectName === "editText")
                        return child.children[j]
                }
            }
        }
        return null
    }

    function getModelIndexForEntry(entryIdx) {
        for (var i = 0; i < terminalModel.count; i++) {
            if (terminalModel.get(i).entryIndex === entryIdx) return i
        }
        return -1
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

        if (root.showPrefix) {
            switch (entry.type) {
            case "rx":     line += "RX> "; break
            case "tx":     line += "TX> "; break
            case "system": line += "SYS> "; break
            case "error":  line += "ERR> "; break
            default:       line += "> "
            }
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

    function copyToClipboardInline(text) {
        clipHelper.text = text
        clipHelper.selectAll()
        clipHelper.copy()
        clipHelper.text = ""

        var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
        addTerminalEntry(ts, "Copied to clipboard (" + text.length + " chars)", "", "system")
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
        syncKeywordsToConfig()
    }

    function addWhitelist(text) {
        text = text.trim()
        if (text === "") return
        whitelistModel.append({ text: text })
        syncWhitelistToConfig()
    }

    function addBlacklist(text) {
        text = text.trim()
        if (text === "") return
        blacklistModel.append({ text: text })
        syncBlacklistToConfig()
    }

    // ── Config sync helpers ────────────────────────────────────
    function syncKeywordsToConfig() {
        var list = []
        for (var i = 0; i < keywordModel.count; i++) {
            var item = keywordModel.get(i)
            list.push({ text: item.text, color: item.color })
        }
        configManager.setKeywords(list)
    }

    function syncWhitelistToConfig() {
        var list = []
        for (var i = 0; i < whitelistModel.count; i++)
            list.push({ text: whitelistModel.get(i).text })
        configManager.setWhitelist(list)
    }

    function syncBlacklistToConfig() {
        var list = []
        for (var i = 0; i < blacklistModel.count; i++)
            list.push({ text: blacklistModel.get(i).text })
        configManager.setBlacklist(list)
    }

    function loadConfigToUI() {
        root.uiScale = configManager.uiScale
        root.terminalFontSize = configManager.terminalFontSize
        root.applyTheme(configManager.currentTheme)

        keywordModel.clear()
        var kws = configManager.keywords()
        for (var i = 0; i < kws.length; i++)
            keywordModel.append({ text: kws[i].text, color: kws[i].color })
        root.kwColorIndex = kws.length
        root.keywordRevision++

        whitelistModel.clear()
        var wl = configManager.whitelist()
        for (var j = 0; j < wl.length; j++)
            whitelistModel.append({ text: wl[j].text })

        blacklistModel.clear()
        var bl = configManager.blacklist()
        for (var k = 0; k < bl.length; k++)
            blacklistModel.append({ text: bl[k].text })
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

    // Boot sequence on startup
    Component.onCompleted: {
        loadConfigToUI()
        var ts = Qt.formatDateTime(new Date(), "HH:mm:ss.zzz")
        addTerminalEntry(ts, "UART PRO v0.1 // SERIAL TERMINAL INTERFACE", "", "system")
        addTerminalEntry(ts, "System initialized. Ready for connection.", "", "system")
        addTerminalEntry(ts, "Config: " + configManager.configFilePath, "", "system")
        addTerminalEntry(ts, "Select a port and click CONNECT to begin.", "", "system")
        serialManager.refreshPorts()
    }
}
